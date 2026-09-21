-- ============================================================================
-- 03_cast_sessions.sql
-- CineBall Web Cast: pairing a phone with a browser on a TV or computer.
--
-- The browser opens /cast, which creates a session and shows a six-digit
-- code. The phone claims that code and from then on the two talk over
-- Supabase Realtime: the phone sends commands, the receiver reports back
-- where playback is.
--
-- Nothing here ever holds a playable URL. The phone resolves the stream at
-- the moment it starts casting and sends it over Realtime, which is not
-- stored; the row keeps only what a remote control needs to draw itself
-- (title, poster, position) so a reconnecting phone can pick up where it
-- left off.
-- ============================================================================

-- ---------------------------------------------------------------- sessions
CREATE TABLE IF NOT EXISTS public.cast_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- What the viewer types on the phone, or what the QR carries. Six digits,
  -- unique only among sessions still waiting (see the partial index below):
  -- a code may be handed out again once its session is claimed or expired.
  pairing_code text NOT NULL CHECK (pairing_code ~ '^[0-9]{6}$'),

  -- Set when a phone claims the session. Null while it waits, and null for
  -- a viewer who is not signed in — the app does not require an account.
  user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,

  -- How the receiver describes itself: 'Chrome on Windows', 'Safari on Mac'.
  device_name text NOT NULL DEFAULT 'الكمبيوتر',
  device_kind text NOT NULL DEFAULT 'web',

  status text NOT NULL DEFAULT 'waiting'
    CHECK (status IN ('waiting', 'paired', 'playing', 'paused', 'disconnected')),

  -- What is on screen, for a remote that has just reconnected. Title,
  -- poster and duration only — never a stream URL.
  media_title text,
  media_poster text,
  media_id text,
  is_live boolean NOT NULL DEFAULT false,
  position_seconds double precision NOT NULL DEFAULT 0,
  duration_seconds double precision,

  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen timestamptz NOT NULL DEFAULT now(),

  -- A session nobody claims dies in ten minutes. Claiming it pushes this
  -- out (see claim_cast_session), and each heartbeat pushes it out again,
  -- so a session in use never expires under the viewer.
  expires_at timestamptz NOT NULL DEFAULT now() + interval '10 minutes'
);

-- Only one session may be waiting on a given code at a time; a claimed or
-- expired session keeps its code without blocking a new one.
CREATE UNIQUE INDEX IF NOT EXISTS idx_cast_sessions_code_waiting
  ON public.cast_sessions (pairing_code)
  WHERE status = 'waiting';

CREATE INDEX IF NOT EXISTS idx_cast_sessions_user ON public.cast_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_cast_sessions_expires ON public.cast_sessions(expires_at);
CREATE INDEX IF NOT EXISTS idx_cast_sessions_status ON public.cast_sessions(status);

ALTER TABLE public.cast_sessions ENABLE ROW LEVEL SECURITY;

-- The receiver is a browser with no account, so it must be able to open a
-- session anonymously. It may only open one that is waiting, unclaimed and
-- carrying no media.
DROP POLICY IF EXISTS "anyone may open a waiting session" ON public.cast_sessions;
CREATE POLICY "anyone may open a waiting session"
  ON public.cast_sessions FOR INSERT
  WITH CHECK (
    status = 'waiting'
    AND user_id IS NULL
    AND media_id IS NULL
  );

-- Reading a session means knowing its id — an unguessable uuid the browser
-- generated and the phone learned by scanning it. A signed-in owner may
-- always read their own. Expired rows are invisible to everyone.
DROP POLICY IF EXISTS "a session is readable to whoever holds it" ON public.cast_sessions;
CREATE POLICY "a session is readable to whoever holds it"
  ON public.cast_sessions FOR SELECT
  USING (
    expires_at > now()
    AND (user_id IS NULL OR user_id = auth.uid())
  );

-- Once a session belongs to somebody, only they may drive it. While it is
-- still unclaimed, whoever holds the id may — that is the receiver itself
-- reporting its state, and the phone claiming it.
DROP POLICY IF EXISTS "only the holder may drive a session" ON public.cast_sessions;
CREATE POLICY "only the holder may drive a session"
  ON public.cast_sessions FOR UPDATE
  USING (
    expires_at > now()
    AND (user_id IS NULL OR user_id = auth.uid())
  )
  WITH CHECK (
    user_id IS NULL OR user_id = auth.uid()
  );

DROP POLICY IF EXISTS "only the holder may end a session" ON public.cast_sessions;
CREATE POLICY "only the holder may end a session"
  ON public.cast_sessions FOR DELETE
  USING (user_id IS NULL OR user_id = auth.uid());

-- ------------------------------------------------------------- claiming it
-- The phone hands over a code, not an id: it has no way to read a row by
-- code (the select policy needs the id), so the claim runs here with the
-- table owner's rights and gives back the session only on an exact match.
--
-- SECURITY DEFINER with a pinned search_path: the function must not be
-- reachable through a schema the caller controls.
CREATE OR REPLACE FUNCTION public.claim_cast_session(
  code text,
  claimed_device_name text DEFAULT NULL
)
RETURNS public.cast_sessions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  claimed public.cast_sessions;
BEGIN
  UPDATE public.cast_sessions AS s
     SET user_id    = auth.uid(),
         status     = 'paired',
         last_seen  = now(),
         device_name = COALESCE(claimed_device_name, s.device_name),
         -- a session in use lives as long as it keeps reporting in
         expires_at = now() + interval '6 hours'
   WHERE s.pairing_code = code
     AND s.status = 'waiting'
     AND s.user_id IS NULL
     AND s.expires_at > now()
  RETURNING s.* INTO claimed;

  IF claimed.id IS NULL THEN
    RAISE EXCEPTION 'pairing code not found or expired'
      USING ERRCODE = 'no_data_found';
  END IF;

  RETURN claimed;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_cast_session(text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.claim_cast_session(text, text) TO anon, authenticated;

-- --------------------------------------------------------------- heartbeat
-- Both ends call this while a session is in use. It is what keeps the
-- session from expiring, so a session stops living the moment both sides
-- stop talking — no separate disconnect is needed for the common case.
CREATE OR REPLACE FUNCTION public.touch_cast_session(session_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE public.cast_sessions
     SET last_seen  = now(),
         expires_at = GREATEST(expires_at, now() + interval '30 minutes')
   WHERE id = session_id
     AND (user_id IS NULL OR user_id = auth.uid());
$$;

REVOKE ALL ON FUNCTION public.touch_cast_session(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.touch_cast_session(uuid) TO anon, authenticated;

-- ----------------------------------------------------------------- cleanup
-- Expired sessions are already invisible to every policy; this is what
-- actually removes them. Call it from a scheduled job (pg_cron) if the
-- project has one, or leave it — the table stays small either way.
CREATE OR REPLACE FUNCTION public.purge_expired_cast_sessions()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  removed integer;
BEGIN
  DELETE FROM public.cast_sessions WHERE expires_at < now() - interval '1 hour';
  GET DIAGNOSTICS removed = ROW_COUNT;
  RETURN removed;
END;
$$;

REVOKE ALL ON FUNCTION public.purge_expired_cast_sessions() FROM public;

-- Commands travel over Realtime broadcast, not through a table: an order to
-- pause must not wait on a write, and there is no reason to keep a log of
-- every seek. The row above is the durable part — what is playing and where
-- — so a phone that reconnects can rebuild its remote without replaying
-- anything.
ALTER PUBLICATION supabase_realtime ADD TABLE public.cast_sessions;

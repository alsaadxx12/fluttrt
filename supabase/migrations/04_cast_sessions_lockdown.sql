-- ============================================================================
-- 04_cast_sessions_lockdown.sql
--
-- Closes a hole in 03: its SELECT policy let any anonymous client list every
-- waiting session together with its pairing code, so a stranger holding
-- nothing but the app's public key could claim somebody else's screen and
-- cast to it. Verified against the live project before writing this.
--
-- Row-level security cannot express "the caller knows this row's id" — a
-- policy that permits reading one row permits listing them all. So the table
-- is closed to clients entirely and every operation goes through a function
-- that demands the session's id or its code. Neither can be guessed: the id
-- is a uuid, and a code only exists for ten minutes and dies when claimed.
--
-- The receiver no longer learns it has been paired by watching the row
-- (Realtime honours RLS, and a closed table reports nothing). The phone tells
-- it, over the broadcast channel the two already share.
-- ============================================================================

-- The table is no longer readable or writable from a client under any policy.
DROP POLICY IF EXISTS "anyone may open a waiting session"   ON public.cast_sessions;
DROP POLICY IF EXISTS "a session is readable to whoever holds it" ON public.cast_sessions;
DROP POLICY IF EXISTS "only the holder may drive a session" ON public.cast_sessions;
DROP POLICY IF EXISTS "only the holder may end a session"   ON public.cast_sessions;

-- RLS stays on with no policies at all: that denies everything to anon and
-- authenticated, while SECURITY DEFINER functions below still reach the rows.
ALTER TABLE public.cast_sessions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.cast_sessions FROM anon, authenticated;

-- Realtime would publish row changes to anyone subscribed; with the table
-- closed it has nothing to say, and the phone announces the pairing itself.
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime DROP TABLE public.cast_sessions;
EXCEPTION
  WHEN undefined_object THEN NULL;
END $$;

-- ------------------------------------------------------------- opening one
-- The receiver calls this instead of inserting. It picks the code itself, so
-- no client chooses one, and returns only what that screen needs to draw its
-- pairing panel.
CREATE OR REPLACE FUNCTION public.open_cast_session(
  name_of_device text DEFAULT 'الكمبيوتر'
)
RETURNS TABLE (id uuid, pairing_code text, expires_at timestamptz)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  code text;
  tries integer := 0;
BEGIN
  LOOP
    tries := tries + 1;
    code := lpad((floor(random() * 900000) + 100000)::int::text, 6, '0');
    BEGIN
      RETURN QUERY
        INSERT INTO public.cast_sessions (pairing_code, device_name, device_kind)
        VALUES (code, COALESCE(NULLIF(btrim(name_of_device), ''), 'الكمبيوتر'), 'web')
        RETURNING cast_sessions.id, cast_sessions.pairing_code, cast_sessions.expires_at;
      RETURN;
    EXCEPTION WHEN unique_violation THEN
      -- that code is already waiting on another screen; take another
      IF tries >= 10 THEN RAISE; END IF;
    END;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.open_cast_session(text) FROM public;
GRANT EXECUTE ON FUNCTION public.open_cast_session(text) TO anon, authenticated;

-- ------------------------------------------------------- reading one back
-- Only ever one row, and only for a caller who already holds its id.
CREATE OR REPLACE FUNCTION public.get_cast_session(session_id uuid)
RETURNS TABLE (
  id uuid,
  status text,
  device_name text,
  media_title text,
  media_poster text,
  media_id text,
  is_live boolean,
  position_seconds double precision,
  duration_seconds double precision
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT s.id, s.status, s.device_name, s.media_title, s.media_poster,
         s.media_id, s.is_live, s.position_seconds, s.duration_seconds
    FROM public.cast_sessions s
   WHERE s.id = session_id
     AND s.expires_at > now();
$$;

REVOKE ALL ON FUNCTION public.get_cast_session(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.get_cast_session(uuid) TO anon, authenticated;

-- --------------------------------------------------------- what is playing
-- The receiver records what is on screen so a phone that comes back can
-- rebuild its remote. Still no stream url — title, poster and position only.
CREATE OR REPLACE FUNCTION public.report_cast_session(
  session_id uuid,
  new_status text DEFAULT NULL,
  title text DEFAULT NULL,
  poster text DEFAULT NULL,
  media text DEFAULT NULL,
  live boolean DEFAULT NULL,
  position_s double precision DEFAULT NULL,
  duration_s double precision DEFAULT NULL
)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE public.cast_sessions s
     SET status            = COALESCE(new_status, s.status),
         media_title       = COALESCE(title, s.media_title),
         media_poster      = COALESCE(poster, s.media_poster),
         media_id          = COALESCE(media, s.media_id),
         is_live           = COALESCE(live, s.is_live),
         position_seconds  = COALESCE(position_s, s.position_seconds),
         duration_seconds  = COALESCE(duration_s, s.duration_seconds),
         last_seen         = now(),
         expires_at        = GREATEST(s.expires_at, now() + interval '30 minutes')
   WHERE s.id = session_id
     AND s.expires_at > now();
$$;

REVOKE ALL ON FUNCTION public.report_cast_session(uuid, text, text, text, text, boolean, double precision, double precision) FROM public;
GRANT EXECUTE ON FUNCTION public.report_cast_session(uuid, text, text, text, text, boolean, double precision, double precision) TO anon, authenticated;

-- ---------------------------------------------------------------- claiming
-- Unchanged in spirit, but it no longer hands back the whole row (which
-- would leak the code to whoever asked) and it no longer needs the caller to
-- be able to read the table.
--
-- Dropped first, not replaced: 03 returned the whole row and Postgres will
-- not let CREATE OR REPLACE change a function's return type. Dropping also
-- drops its grants, so they are given again below.
DROP FUNCTION IF EXISTS public.claim_cast_session(text, text);

CREATE FUNCTION public.claim_cast_session(
  code text,
  claimed_device_name text DEFAULT NULL
)
RETURNS TABLE (id uuid, device_name text, status text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  -- Locals rather than RETURN QUERY: the OUT names of a RETURNS TABLE are
  -- variables inside the body, and Postgres will not let one stand where a
  -- column of the same name could be meant.
  found_id uuid;
  found_name text;
BEGIN
  UPDATE public.cast_sessions AS s
     SET user_id     = auth.uid(),
         status      = 'paired',
         last_seen   = now(),
         device_name = COALESCE(NULLIF(btrim(claimed_device_name), ''), s.device_name),
         expires_at  = now() + interval '6 hours'
   WHERE s.pairing_code = code
     AND s.status = 'waiting'
     AND s.user_id IS NULL
     AND s.expires_at > now()
  RETURNING s.id, s.device_name INTO found_id, found_name;

  IF found_id IS NULL THEN
    RAISE EXCEPTION 'pairing code not found or expired'
      USING ERRCODE = 'no_data_found';
  END IF;

  id := found_id;
  device_name := found_name;
  status := 'paired';
  RETURN NEXT;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_cast_session(text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.claim_cast_session(text, text) TO anon, authenticated;

-- --------------------------------------------------------------- ending it
CREATE OR REPLACE FUNCTION public.end_cast_session(session_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE public.cast_sessions
     SET status = 'disconnected', last_seen = now()
   WHERE id = session_id;
$$;

REVOKE ALL ON FUNCTION public.end_cast_session(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.end_cast_session(uuid) TO anon, authenticated;

-- touch_cast_session no longer depends on who owns the row: holding the id
-- is the credential, the same as everywhere else here.
CREATE OR REPLACE FUNCTION public.touch_cast_session(session_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  UPDATE public.cast_sessions
     SET last_seen  = now(),
         expires_at = GREATEST(expires_at, now() + interval '30 minutes')
   WHERE id = session_id;
$$;

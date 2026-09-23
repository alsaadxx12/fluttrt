-- ============================================================================
-- 06_watch_history.sql
-- Table: watch_history (what each user watched, and how far they got)
--
-- One row per user and title. A series is one row, updated with whichever
-- episode was watched last; the position is where that episode was left,
-- so the next device picks it up from the same minute.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.watch_history (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  item_id text NOT NULL,
  video_id text NOT NULL,
  item_data jsonb NOT NULL,
  episode_label text NOT NULL DEFAULT '',
  position_seconds integer NOT NULL DEFAULT 0,
  duration_seconds integer NOT NULL DEFAULT 0,
  watched_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(user_id, item_id)
);

CREATE INDEX IF NOT EXISTS idx_watch_history_user_id ON public.watch_history(user_id);
CREATE INDEX IF NOT EXISTS idx_watch_history_watched_at ON public.watch_history(watched_at DESC);

ALTER TABLE public.watch_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read own history" ON public.watch_history;
CREATE POLICY "Users can read own history"
  ON public.watch_history FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can insert own history" ON public.watch_history;
CREATE POLICY "Users can insert own history"
  ON public.watch_history FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can update own history" ON public.watch_history;
CREATE POLICY "Users can update own history"
  ON public.watch_history FOR UPDATE
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users can delete own history" ON public.watch_history;
CREATE POLICY "Users can delete own history"
  ON public.watch_history FOR DELETE
  USING (auth.uid() = user_id);

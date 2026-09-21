-- ============================================================================
-- CineBall - Supabase Database Schema & Migration
-- Tables: profiles, activation_codes, sports_subscriptions, activation_redemptions
-- RPC: redeem_activation_code, get_user_sports_subscription, create_activation_code_raw
-- Security: Row Level Security (RLS) + Atomic Transactions
-- ============================================================================

-- 1. Enable Required Extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ============================================================================
-- 2. Profiles Table (linked to auth.users)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name text NOT NULL DEFAULT '',
  phone text UNIQUE NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- ============================================================================
-- 3. Activation Codes Table (Hashes stored securely, plaintext never stored)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.activation_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code_hash text UNIQUE NOT NULL,
  duration_days integer NOT NULL CHECK (duration_days > 0),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'disabled', 'expired', 'fully_used')),
  max_uses integer NOT NULL DEFAULT 1 CHECK (max_uses > 0),
  used_count integer NOT NULL DEFAULT 0 CHECK (used_count >= 0),
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_activation_codes_hash ON public.activation_codes(code_hash);
CREATE INDEX IF NOT EXISTS idx_activation_codes_status ON public.activation_codes(status);

-- ============================================================================
-- 4. Sports Subscriptions Table (Source of truth on Supabase)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.sports_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  activation_code_id uuid REFERENCES public.activation_codes(id) ON DELETE SET NULL,
  started_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'expired', 'cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sports_sub_user ON public.sports_subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_sports_sub_status ON public.sports_subscriptions(status);

-- ============================================================================
-- 5. Activation Redemptions Table (Audit log of redemptions)
-- ============================================================================
CREATE TABLE IF NOT EXISTS public.activation_redemptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  activation_code_id uuid NOT NULL REFERENCES public.activation_codes(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  redeemed_at timestamptz NOT NULL DEFAULT now(),
  subscription_start timestamptz NOT NULL,
  subscription_end timestamptz NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_redemptions_user ON public.activation_redemptions(user_id);
CREATE INDEX IF NOT EXISTS idx_redemptions_code ON public.activation_redemptions(activation_code_id);

-- ============================================================================
-- 6. Row Level Security (RLS)
-- ============================================================================
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activation_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.sports_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.activation_redemptions ENABLE ROW LEVEL SECURITY;

-- Profiles: users can read & update only their own profile
DROP POLICY IF EXISTS "Users can read their own profile" ON public.profiles;
CREATE POLICY "Users can read their own profile"
  ON public.profiles FOR SELECT
  USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can update their own profile" ON public.profiles;
CREATE POLICY "Users can update their own profile"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id);

DROP POLICY IF EXISTS "Users can insert their own profile" ON public.profiles;
CREATE POLICY "Users can insert their own profile"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

-- Sports Subscriptions: users can only read their own subscription
DROP POLICY IF EXISTS "Users can read own subscription" ON public.sports_subscriptions;
CREATE POLICY "Users can read own subscription"
  ON public.sports_subscriptions FOR SELECT
  USING (auth.uid() = user_id);

-- Activation Redemptions: users can read their own redemption history
DROP POLICY IF EXISTS "Users can read own redemptions" ON public.activation_redemptions;
CREATE POLICY "Users can read own redemptions"
  ON public.activation_redemptions FOR SELECT
  USING (auth.uid() = user_id);

-- Activation Codes: strictly locked! No direct client SELECT/INSERT/UPDATE/DELETE.
-- All access happens through secure SECURITY DEFINER RPC functions.

-- ============================================================================
-- 7. Auth User Triggers (Auto Profile Creation & Instant Auto Confirmation)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, phone, created_at, updated_at)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    COALESCE(NEW.raw_user_meta_data->>'phone', ''),
    now(),
    now()
  )
  ON CONFLICT (id) DO UPDATE
  SET full_name = CASE WHEN EXCLUDED.full_name <> '' THEN EXCLUDED.full_name ELSE public.profiles.full_name END,
      phone = CASE WHEN EXCLUDED.phone <> '' THEN EXCLUDED.phone ELSE public.profiles.phone END,
      updated_at = now();

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Auto Confirm User (No Email/SMS Verification Needed)
CREATE OR REPLACE FUNCTION public.auto_confirm_user()
RETURNS trigger AS $$
BEGIN
  NEW.email_confirmed_at = COALESCE(NEW.email_confirmed_at, now());
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_auto_confirm ON auth.users;
CREATE TRIGGER on_auth_user_auto_confirm
  BEFORE INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.auto_confirm_user();

-- ============================================================================
-- 8. Atomic Activation Redemption RPC Function
-- ============================================================================
CREATE OR REPLACE FUNCTION public.redeem_activation_code(code_input text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_clean_code text;
  v_code_hash text;
  v_code record;
  v_already_redeemed boolean;
  v_existing_sub record;
  v_sub_start timestamptz;
  v_sub_end timestamptz;
BEGIN
  -- 1. Verify user identity
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'UNAUTHORIZED',
      'message', 'يجب تسجيل الدخول أولاً.'
    );
  END IF;

  -- 2. Validate input
  IF code_input IS NULL OR trim(code_input) = '' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'EMPTY_CODE',
      'message', 'يرجى إدخال كود التفعيل.'
    );
  END IF;

  -- 3. Normalize code: uppercase and strip all spaces and dashes
  v_clean_code := upper(regexp_replace(code_input, '[\s\-_]+', '', 'g'));
  v_code_hash := encode(digest(v_clean_code, 'sha256'), 'hex');

  -- 4. Atomic row lock on activation_codes
  SELECT * INTO v_code
  FROM public.activation_codes
  WHERE code_hash = v_code_hash
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'INVALID_CODE',
      'message', 'كود التفعيل غير صحيح.'
    );
  END IF;

  -- 5. Status checks
  IF v_code.status = 'disabled' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'DISABLED',
      'message', 'كود التفعيل غير متاح.'
    );
  END IF;

  IF (v_code.expires_at IS NOT NULL AND v_code.expires_at <= now()) OR v_code.status = 'expired' THEN
    IF v_code.status != 'expired' THEN
      UPDATE public.activation_codes SET status = 'expired' WHERE id = v_code.id;
    END IF;
    RETURN jsonb_build_object(
      'success', false,
      'error', 'EXPIRED',
      'message', 'انتهت صلاحية كود التفعيل.'
    );
  END IF;

  IF v_code.used_count >= v_code.max_uses OR v_code.status = 'fully_used' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'ALREADY_USED',
      'message', 'تم استخدام كود التفعيل مسبقًا.'
    );
  END IF;

  -- 6. Check if user already redeemed this exact code
  SELECT EXISTS (
    SELECT 1 FROM public.activation_redemptions
    WHERE activation_code_id = v_code.id AND user_id = v_user_id
  ) INTO v_already_redeemed;

  IF v_already_redeemed THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'ALREADY_REDEEMED',
      'message', 'تم استخدام كود التفعيل مسبقًا على هذا الحساب.'
    );
  END IF;

  -- 7. Calculate cumulative duration
  SELECT * INTO v_existing_sub
  FROM public.sports_subscriptions
  WHERE user_id = v_user_id
  FOR UPDATE;

  IF v_existing_sub.id IS NOT NULL AND v_existing_sub.status = 'active' AND v_existing_sub.expires_at > now() THEN
    -- User still has active days: append new duration to current expiry
    v_sub_start := v_existing_sub.expires_at;
    v_sub_end := v_existing_sub.expires_at + (v_code.duration_days || ' days')::interval;
  ELSE
    -- Expired or no subscription: start duration from server now
    v_sub_start := now();
    v_sub_end := now() + (v_code.duration_days || ' days')::interval;
  END IF;

  -- 8. Upsert into sports_subscriptions
  INSERT INTO public.sports_subscriptions (
    user_id,
    activation_code_id,
    started_at,
    expires_at,
    status,
    created_at,
    updated_at
  )
  VALUES (
    v_user_id,
    v_code.id,
    LEAST(COALESCE(v_existing_sub.started_at, now()), now()),
    v_sub_end,
    'active',
    now(),
    now()
  )
  ON CONFLICT (user_id) DO UPDATE
  SET activation_code_id = EXCLUDED.activation_code_id,
      expires_at = EXCLUDED.expires_at,
      status = 'active',
      updated_at = now();

  -- 9. Insert audit redemption log
  INSERT INTO public.activation_redemptions (
    activation_code_id,
    user_id,
    redeemed_at,
    subscription_start,
    subscription_end
  )
  VALUES (
    v_code.id,
    v_user_id,
    now(),
    v_sub_start,
    v_sub_end
  );

  -- 10. Increment used_count and update code status
  UPDATE public.activation_codes
  SET used_count = used_count + 1,
      status = CASE WHEN used_count + 1 >= max_uses THEN 'fully_used' ELSE status END
  WHERE id = v_code.id;

  -- 11. Return clean success payload
  RETURN jsonb_build_object(
    'success', true,
    'message', 'تم تفعيل الاشتراك بنجاح.',
    'expires_at', v_sub_end,
    'duration_days', v_code.duration_days,
    'status', 'active'
  );
END;
$$;

-- Grant execution to authenticated users
GRANT EXECUTE ON FUNCTION public.redeem_activation_code(text) TO authenticated;

-- ============================================================================
-- 9. Secure Subscription Status RPC Function
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_user_sports_subscription()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_sub record;
  v_is_active boolean;
  v_remaining_days integer;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'has_subscription', false,
      'is_active', false,
      'status', 'none'
    );
  END IF;

  SELECT * INTO v_sub
  FROM public.sports_subscriptions
  WHERE user_id = v_user_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'has_subscription', false,
      'is_active', false,
      'status', 'none'
    );
  END IF;

  IF v_sub.status = 'active' AND v_sub.expires_at > now() THEN
    v_is_active := true;
    v_remaining_days := CEIL(EXTRACT(EPOCH FROM (v_sub.expires_at - now())) / 86400)::integer;
  ELSE
    v_is_active := false;
    v_remaining_days := 0;
    IF v_sub.status = 'active' THEN
      UPDATE public.sports_subscriptions
      SET status = 'expired', updated_at = now()
      WHERE id = v_sub.id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'has_subscription', true,
    'is_active', v_is_active,
    'status', CASE WHEN v_is_active THEN 'active' ELSE 'expired' END,
    'started_at', v_sub.started_at,
    'expires_at', v_sub.expires_at,
    'remaining_days', v_remaining_days,
    'server_now', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_user_sports_subscription() TO authenticated;

-- ============================================================================
-- 10. Admin Helper to Generate Test Activation Codes
-- ============================================================================
CREATE OR REPLACE FUNCTION public.create_activation_code_raw(
  p_code text,
  p_duration_days integer DEFAULT 30,
  p_max_uses integer DEFAULT 1
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_clean text;
  v_hash text;
BEGIN
  v_clean := upper(regexp_replace(p_code, '[\s\-_]+', '', 'g'));
  v_hash := encode(digest(v_clean, 'sha256'), 'hex');

  INSERT INTO public.activation_codes (code_hash, duration_days, max_uses, status)
  VALUES (v_hash, p_duration_days, p_max_uses, 'active')
  ON CONFLICT (code_hash) DO UPDATE
  SET duration_days = EXCLUDED.duration_days,
      max_uses = EXCLUDED.max_uses,
      status = 'active',
      used_count = 0;

  RETURN 'Code created successfully: ' || upper(p_code);
END;
$$;

-- Seed Sample Testing Codes
SELECT public.create_activation_code_raw('CINE-7K4M-92PX', 30, 1);
SELECT public.create_activation_code_raw('CINE-ABCD-8291', 30, 1);
SELECT public.create_activation_code_raw('CINE-RENEW-30D', 30, 1);
SELECT public.create_activation_code_raw('CINE-MULTI-TEST', 30, 10);

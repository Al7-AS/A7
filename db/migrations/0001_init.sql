-- =====================================================================
-- LearnSphere - initial schema (PostgreSQL 15+)
-- Multi-tenant: every tenant-owned row carries tenant_id and is
-- protected by Row Level Security (RLS) keyed on app.current_tenant_id.
-- =====================================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "citext";

-- ---------- Enumerations ----------
CREATE TYPE user_status        AS ENUM ('pending_verification', 'active', 'suspended');
CREATE TYPE tenant_status      AS ENUM ('trialing', 'active', 'suspended', 'closed');
CREATE TYPE subscription_status AS ENUM ('trialing', 'active', 'past_due', 'canceled', 'expired');
CREATE TYPE course_status      AS ENUM ('draft', 'published', 'unpublished', 'archived');
CREATE TYPE course_difficulty  AS ENUM ('beginner', 'intermediate', 'advanced');
CREATE TYPE lesson_type        AS ENUM ('video', 'text', 'pdf', 'download', 'external', 'quiz');
CREATE TYPE question_type      AS ENUM ('multiple_choice', 'true_false', 'short_answer');
CREATE TYPE enrollment_status  AS ENUM ('active', 'completed', 'revoked');
CREATE TYPE payment_status     AS ENUM ('pending', 'succeeded', 'failed', 'refunded', 'partially_refunded');
CREATE TYPE submission_status  AS ENUM ('submitted', 'graded', 'returned');
CREATE TYPE session_status     AS ENUM ('scheduled', 'live', 'ended', 'canceled');

-- ---------- Platform level (not tenant-scoped) ----------
CREATE TABLE users (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email           citext NOT NULL UNIQUE,
  password_hash   text NOT NULL,
  full_name       text NOT NULL,
  locale          text NOT NULL DEFAULT 'ar' CHECK (locale IN ('ar', 'en')),
  status          user_status NOT NULL DEFAULT 'pending_verification',
  email_verified_at timestamptz,
  is_super_admin  boolean NOT NULL DEFAULT false,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE plans (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code                text NOT NULL UNIQUE,              -- starter | professional | business | enterprise
  name                text NOT NULL,
  price_monthly_cents integer NOT NULL CHECK (price_monthly_cents >= 0),
  currency            char(3) NOT NULL DEFAULT 'EGP',
  max_students        integer,                           -- NULL = unlimited
  max_instructors     integer,
  max_courses         integer,
  storage_mb          integer,
  advanced_analytics  boolean NOT NULL DEFAULT false,
  custom_branding     boolean NOT NULL DEFAULT false,
  integrations        text[] NOT NULL DEFAULT '{}',
  is_active           boolean NOT NULL DEFAULT true,
  updated_at          timestamptz NOT NULL DEFAULT now()
);

-- ---------- Tenants (institutions / instructor workspaces) ----------
CREATE TABLE tenants (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug          text NOT NULL UNIQUE CHECK (slug ~ '^[a-z0-9-]{3,40}$'),
  name          text NOT NULL,
  status        tenant_status NOT NULL DEFAULT 'trialing',
  brand_settings jsonb NOT NULL DEFAULT '{}'::jsonb,   -- logo, colors, default locale
  created_by    uuid REFERENCES users(id),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE roles (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code        text NOT NULL UNIQUE,  -- super_admin | institution_owner | instructor | student | parent
  name        text NOT NULL
);

CREATE TABLE permissions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code        text NOT NULL UNIQUE,  -- e.g. courses:write, finance:read
  description text
);

CREATE TABLE role_permissions (
  role_id       uuid NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  permission_id uuid NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, permission_id)
);

-- Membership of a user inside a tenant, with that tenant's role.
CREATE TABLE tenant_members (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role_id     uuid NOT NULL REFERENCES roles(id),
  invited_by  uuid REFERENCES users(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, user_id)
);
CREATE INDEX idx_tenant_members_user ON tenant_members(user_id);

-- Parent <-> student links (within one tenant).
CREATE TABLE parent_links (
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  parent_id   uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  student_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  PRIMARY KEY (tenant_id, parent_id, student_id)
);

CREATE TABLE subscriptions (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  plan_id             uuid NOT NULL REFERENCES plans(id),
  status              subscription_status NOT NULL DEFAULT 'trialing',
  trial_ends_at       timestamptz,
  current_period_start timestamptz NOT NULL DEFAULT now(),
  current_period_end  timestamptz NOT NULL,
  canceled_at         timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX uq_one_open_subscription
  ON subscriptions(tenant_id) WHERE status IN ('trialing', 'active', 'past_due');

-- ---------- Catalog ----------
CREATE TABLE courses (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  instructor_id   uuid NOT NULL REFERENCES users(id),
  title           text NOT NULL CHECK (length(title) BETWEEN 3 AND 200),
  description     text NOT NULL DEFAULT '',
  category        text,
  cover_url       text,
  price_cents     integer NOT NULL DEFAULT 0 CHECK (price_cents >= 0),
  discount_cents  integer CHECK (discount_cents >= 0),
  currency        char(3) NOT NULL DEFAULT 'EGP',
  difficulty      course_difficulty NOT NULL DEFAULT 'beginner',
  duration_minutes integer NOT NULL DEFAULT 0 CHECK (duration_minutes >= 0),
  language        text NOT NULL DEFAULT 'ar' CHECK (language IN ('ar', 'en')),
  objectives      text[] NOT NULL DEFAULT '{}',
  requirements    text[] NOT NULL DEFAULT '{}',
  status          course_status NOT NULL DEFAULT 'draft',
  published_at    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CHECK (discount_cents IS NULL OR discount_cents <= price_cents)
);
CREATE INDEX idx_courses_tenant_status ON courses(tenant_id, status);
CREATE INDEX idx_courses_instructor ON courses(tenant_id, instructor_id);

CREATE TABLE course_sections (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  course_id   uuid NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  title       text NOT NULL,
  position    integer NOT NULL CHECK (position >= 0),
  UNIQUE (course_id, position) DEFERRABLE INITIALLY DEFERRED
);
CREATE INDEX idx_sections_tenant ON course_sections(tenant_id);

CREATE TABLE lessons (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  section_id      uuid NOT NULL REFERENCES course_sections(id) ON DELETE CASCADE,
  title           text NOT NULL,
  type            lesson_type NOT NULL,
  content         text,                  -- text body, or video/external URL
  video_url       text,
  duration_seconds integer NOT NULL DEFAULT 0 CHECK (duration_seconds >= 0),
  is_free_preview boolean NOT NULL DEFAULT false,
  position        integer NOT NULL CHECK (position >= 0),
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (section_id, position) DEFERRABLE INITIALLY DEFERRED
);
CREATE INDEX idx_lessons_tenant ON lessons(tenant_id);

CREATE TABLE lesson_resources (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  lesson_id   uuid NOT NULL REFERENCES lessons(id) ON DELETE CASCADE,
  title       text NOT NULL,
  storage_key text,                      -- object key in private bucket
  external_url text,
  is_downloadable boolean NOT NULL DEFAULT true,
  size_bytes  bigint CHECK (size_bytes >= 0),
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_resources_tenant ON lesson_resources(tenant_id);

-- ---------- Enrollment & progress ----------
CREATE TABLE enrollments (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  course_id     uuid NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  student_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  status        enrollment_status NOT NULL DEFAULT 'active',
  enrolled_at   timestamptz NOT NULL DEFAULT now(),
  completed_at  timestamptz,
  UNIQUE (tenant_id, course_id, student_id)
);
CREATE INDEX idx_enrollments_student ON enrollments(tenant_id, student_id);

CREATE TABLE lesson_progress (
  tenant_id       uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  enrollment_id   uuid NOT NULL REFERENCES enrollments(id) ON DELETE CASCADE,
  lesson_id       uuid NOT NULL REFERENCES lessons(id) ON DELETE CASCADE,
  last_position_seconds integer NOT NULL DEFAULT 0 CHECK (last_position_seconds >= 0),
  completed_at    timestamptz,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (enrollment_id, lesson_id)
);

CREATE TABLE lesson_notes (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  lesson_id   uuid NOT NULL REFERENCES lessons(id) ON DELETE CASCADE,
  student_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body        text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ---------- Assessments ----------
CREATE TABLE quizzes (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  course_id       uuid NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  lesson_id       uuid REFERENCES lessons(id) ON DELETE SET NULL,
  title           text NOT NULL,
  time_limit_seconds integer CHECK (time_limit_seconds IS NULL OR time_limit_seconds > 0),
  randomize       boolean NOT NULL DEFAULT false,
  pass_score_percent smallint NOT NULL DEFAULT 50 CHECK (pass_score_percent BETWEEN 0 AND 100),
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE questions (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  quiz_id     uuid NOT NULL REFERENCES quizzes(id) ON DELETE CASCADE,
  type        question_type NOT NULL,
  prompt      text NOT NULL,
  options     jsonb NOT NULL DEFAULT '[]'::jsonb,   -- MCQ choices
  correct_answer jsonb,                             -- index, boolean, or accepted string(s); never sent to students
  points      smallint NOT NULL DEFAULT 1 CHECK (points > 0),
  position    integer NOT NULL DEFAULT 0,
  CHECK (type <> 'short_answer' OR correct_answer IS NULL OR jsonb_typeof(correct_answer) IN ('array', 'string'))
);

CREATE TABLE quiz_attempts (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  quiz_id       uuid NOT NULL REFERENCES quizzes(id) ON DELETE CASCADE,
  student_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  answers       jsonb NOT NULL DEFAULT '{}'::jsonb,
  score_percent numeric(5,2),
  started_at    timestamptz NOT NULL DEFAULT now(),
  submitted_at  timestamptz,
  graded_by     uuid REFERENCES users(id)
);
CREATE INDEX idx_attempts_student ON quiz_attempts(tenant_id, student_id);

CREATE TABLE assignments (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  course_id   uuid NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  title       text NOT NULL,
  instructions text NOT NULL DEFAULT '',
  due_at      timestamptz,
  max_points  smallint NOT NULL DEFAULT 100 CHECK (max_points > 0),
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE submissions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  assignment_id uuid NOT NULL REFERENCES assignments(id) ON DELETE CASCADE,
  student_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  body          text,
  file_key      text,                               -- private storage object key
  status        submission_status NOT NULL DEFAULT 'submitted',
  grade         numeric(6,2),
  feedback      text,
  submitted_at  timestamptz NOT NULL DEFAULT now(),
  graded_at     timestamptz,
  graded_by     uuid REFERENCES users(id),
  UNIQUE (assignment_id, student_id)
);

-- ---------- Money ----------
CREATE TABLE coupons (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  code          text NOT NULL,
  percent_off   smallint CHECK (percent_off BETWEEN 1 AND 100),
  amount_off_cents integer CHECK (amount_off_cents > 0),
  max_redemptions integer,
  redemptions   integer NOT NULL DEFAULT 0,
  expires_at    timestamptz,
  is_active     boolean NOT NULL DEFAULT true,
  UNIQUE (tenant_id, code),
  CHECK ((percent_off IS NULL) <> (amount_off_cents IS NULL))
);

CREATE TABLE payments (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  student_id          uuid NOT NULL REFERENCES users(id),
  course_id           uuid NOT NULL REFERENCES courses(id),
  coupon_id           uuid REFERENCES coupons(id),
  amount_cents        integer NOT NULL CHECK (amount_cents >= 0),
  currency            char(3) NOT NULL,
  provider            text NOT NULL CHECK (provider IN ('stripe', 'paymob', 'free')),
  provider_reference  text,
  status              payment_status NOT NULL DEFAULT 'pending',
  verified_at         timestamptz,                  -- set ONLY by a verified webhook
  created_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, provider_reference)
);
CREATE INDEX idx_payments_tenant ON payments(tenant_id, created_at);

-- Ledger: one row per money movement. Platform commission is explicit.
CREATE TABLE transactions (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  payment_id        uuid REFERENCES payments(id),
  kind              text NOT NULL CHECK (kind IN ('sale', 'refund', 'instructor_share', 'platform_commission', 'subscription_charge')),
  amount_cents      integer NOT NULL,
  currency          char(3) NOT NULL,
  created_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_transactions_tenant ON transactions(tenant_id, created_at);

-- ---------- Certificates ----------
CREATE TABLE certificates (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  course_id     uuid NOT NULL REFERENCES courses(id),
  student_id    uuid NOT NULL REFERENCES users(id),
  certificate_code text NOT NULL UNIQUE,            -- public verification ID
  template      jsonb NOT NULL DEFAULT '{}'::jsonb,
  issued_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (course_id, student_id)
);

-- ---------- Live sessions ----------
CREATE TABLE live_sessions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  course_id     uuid NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  instructor_id uuid NOT NULL REFERENCES users(id),
  title         text NOT NULL,
  starts_at     timestamptz NOT NULL,
  duration_minutes integer NOT NULL CHECK (duration_minutes > 0),
  meeting_url   text,
  provider      text NOT NULL DEFAULT 'manual' CHECK (provider IN ('manual', 'zoom')),
  status        session_status NOT NULL DEFAULT 'scheduled',
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE session_reservations (
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  session_id  uuid NOT NULL REFERENCES live_sessions(id) ON DELETE CASCADE,
  student_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  attended_at timestamptz,
  PRIMARY KEY (session_id, student_id)
);

-- ---------- Messaging, notifications, reviews ----------
CREATE TABLE notifications (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  kind        text NOT NULL,
  title       text NOT NULL,
  body        text,
  link        text,
  read_at     timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_notifications_user ON notifications(tenant_id, user_id, read_at);

CREATE TABLE messages (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  sender_id    uuid NOT NULL REFERENCES users(id),
  recipient_id uuid NOT NULL REFERENCES users(id),
  body         text NOT NULL,
  read_at      timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  CHECK (sender_id <> recipient_id)
);

CREATE TABLE reviews (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  course_id   uuid NOT NULL REFERENCES courses(id) ON DELETE CASCADE,
  student_id  uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  rating      smallint NOT NULL CHECK (rating BETWEEN 1 AND 5),
  body        text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (course_id, student_id)
);

-- ---------- Audit ----------
CREATE TABLE audit_logs (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tenant_id   uuid REFERENCES tenants(id) ON DELETE SET NULL,   -- NULL = platform-level action
  actor_id    uuid REFERENCES users(id) ON DELETE SET NULL,
  action      text NOT NULL,
  entity      text NOT NULL,
  entity_id   uuid,
  metadata    jsonb NOT NULL DEFAULT '{}'::jsonb,
  ip_address  inet,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_tenant ON audit_logs(tenant_id, created_at);

-- =====================================================================
-- Row Level Security
-- The application sets, per request/transaction:
--   SELECT set_config('app.current_tenant_id', '<uuid>', true);
--   SELECT set_config('app.current_user_id',   '<uuid>', true);
-- Super admins bypass tenant scope via app.is_super_admin = 'true'
-- (set only by the server after verifying the session).
-- =====================================================================

CREATE OR REPLACE FUNCTION app_current_tenant() RETURNS uuid
LANGUAGE sql STABLE AS $$
  SELECT NULLIF(current_setting('app.current_tenant_id', true), '')::uuid
$$;

CREATE OR REPLACE FUNCTION app_is_super_admin() RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT COALESCE(current_setting('app.is_super_admin', true), 'false') = 'true'
$$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'tenant_members','parent_links','subscriptions','courses','course_sections','lessons',
    'lesson_resources','enrollments','lesson_progress','lesson_notes','quizzes','questions',
    'quiz_attempts','assignments','submissions','coupons','payments','transactions',
    'certificates','live_sessions','session_reservations','notifications','messages',
    'reviews','audit_logs'
  ]
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format($p$
      CREATE POLICY tenant_isolation ON %I
      USING (app_is_super_admin() OR tenant_id = app_current_tenant())
      WITH CHECK (app_is_super_admin() OR tenant_id = app_current_tenant())
    $p$, t);
  END LOOP;
END $$;

-- tenants table: a user sees only tenants they belong to (or all, for super admin).
ALTER TABLE tenants ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenants FORCE ROW LEVEL SECURITY;
CREATE POLICY tenant_row_access ON tenants
  USING (app_is_super_admin() OR id = app_current_tenant())
  WITH CHECK (app_is_super_admin() OR id = app_current_tenant());

-- Seed reference data
INSERT INTO roles (code, name) VALUES
  ('super_admin', 'Super Admin'),
  ('institution_owner', 'Institution Owner'),
  ('instructor', 'Instructor'),
  ('student', 'Student'),
  ('parent', 'Parent');

INSERT INTO plans (code, name, price_monthly_cents, max_students, max_instructors, max_courses, storage_mb, advanced_analytics, custom_branding, integrations) VALUES
  ('starter',      'Starter',      0,       100,  2,    10,   2048,  false, false, '{}'),
  ('professional', 'Professional', 499900,  1000, 10,   100,  20480, true,  true,  '{stripe,paymob}'),
  ('business',     'Business',     1499900, 5000, 30,   500,  102400, true, true,  '{stripe,paymob,zoom}'),
  ('enterprise',   'Enterprise',   0,       NULL, NULL, NULL, NULL,   true,  true,  '{stripe,paymob,zoom,whatsapp}');

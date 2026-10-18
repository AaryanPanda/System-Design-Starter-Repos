-- migrations/001_initial_schema.sql (REPAIRED)
--
-- Correctly implements the Helpdesk ER diagram:
--   * UUID primary keys with DEFAULT gen_random_uuid()
--   * NOT NULL where the ERD requires it
--   * CHECK constraints for every enum column
--   * TIMESTAMPTZ for all timestamps; DEFAULT NOW() for created_at
--   * UUID (not INTEGER) foreign keys
--   * An explicit ON DELETE action on every foreign key
--   * The rejected tags TEXT[] array removed; Tag + TicketTag entities added
--
-- gen_random_uuid() is provided by the pgcrypto extension on older servers;
-- it is built in from PostgreSQL 13+. Enable pgcrypto to be safe.
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- Organization
-- ---------------------------------------------------------------------------
CREATE TABLE organizations (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL,
  plan       TEXT NOT NULL CHECK (plan IN ('starter', 'pro', 'enterprise')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- Agent
-- ---------------------------------------------------------------------------
CREATE TABLE agents (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name           TEXT NOT NULL,
  email          TEXT NOT NULL UNIQUE,
  role           TEXT NOT NULL CHECK (role IN ('agent', 'supervisor', 'admin')),
  org_id         UUID NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deactivated_at TIMESTAMPTZ            -- nullable per ERD
);

-- ---------------------------------------------------------------------------
-- Ticket
-- ---------------------------------------------------------------------------
CREATE TABLE tickets (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subject     TEXT NOT NULL,
  body        TEXT NOT NULL,   -- ERD does not mark it nullable -> required
  priority    TEXT NOT NULL CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
  status      TEXT NOT NULL CHECK (status IN ('open', 'pending', 'resolved', 'closed')) DEFAULT 'open',
  org_id      UUID NOT NULL REFERENCES organizations(id) ON DELETE RESTRICT,
  created_by  UUID NOT NULL REFERENCES agents(id) ON DELETE RESTRICT,
  assignee_id UUID REFERENCES agents(id) ON DELETE SET NULL,   -- nullable
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at TIMESTAMPTZ            -- nullable per ERD
);

-- ---------------------------------------------------------------------------
-- Comment
-- ---------------------------------------------------------------------------
CREATE TABLE comments (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id  UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  author_id  UUID NOT NULL REFERENCES agents(id) ON DELETE RESTRICT,
  body       TEXT NOT NULL,
  internal   BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ---------------------------------------------------------------------------
-- Tag  (replaces the rejected tickets.tags TEXT[] array)
-- ---------------------------------------------------------------------------
CREATE TABLE tags (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  org_id    UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  name      TEXT NOT NULL,
  color_hex TEXT NOT NULL
);

-- ---------------------------------------------------------------------------
-- TicketTag  (join entity resolving the Ticket <-> Tag many-to-many)
-- ---------------------------------------------------------------------------
CREATE TABLE ticket_tags (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id UUID NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  tag_id    UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  added_by  UUID NOT NULL REFERENCES agents(id) ON DELETE RESTRICT,
  added_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (ticket_id, tag_id)   -- a tag is applied to a ticket at most once
);

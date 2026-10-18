# Helpdesk — Schema Repair

`migrations/001_initial_schema.sql` was repaired to correctly implement the
Helpdesk ER diagram (the source of truth): UUID primary keys with
`DEFAULT gen_random_uuid()`, NOT NULL and CHECK constraints from the ERD,
`TIMESTAMPTZ` timestamps with `DEFAULT NOW()` on `created_at`, UUID foreign keys
with an explicit `ON DELETE` on every FK, and the rejected `tags TEXT[]` array
replaced by proper `tags` and `ticket_tags` tables.

## ERD-to-Schema Decisions

### Decision 1: Column type — UUID primary and foreign keys, not SERIAL/INTEGER
ERD said: every entity's `id` is a `uuid` primary key, and every FK (`org_id`,
`created_by`, `assignee_id`, `ticket_id`, `author_id`, `tag_id`, `added_by`)
references a `uuid`.
Schema decided: `UUID PRIMARY KEY DEFAULT gen_random_uuid()` for every table, and
`UUID` for every FK column — never `SERIAL` or `INTEGER`.
Reason: the broken schema used `SERIAL`/`INTEGER`, which contradicts the ERD and
leaks sequential, guessable IDs across tenants. UUIDs are generated server-side by
default and keep each FK's type identical to the PK it references, so joins and
references stay type-correct.

### Decision 2: ON DELETE — `comments.ticket_id` CASCADE vs `comments.author_id` RESTRICT
ERD said: a Ticket "has" comments, and an Agent "authored" comments.
Schema decided: `ticket_id REFERENCES tickets(id) ON DELETE CASCADE`, but
`author_id REFERENCES agents(id) ON DELETE RESTRICT`.
Reason: a comment has no meaning without its ticket, so comments should die with
the ticket (CASCADE). The author, by contrast, is an audit record — we must never
silently lose who wrote a comment — so an agent who still has comments cannot be
deleted (RESTRICT). The same reasoning makes `tickets.created_by` RESTRICT (keep
who filed the ticket) while `tickets.assignee_id` is `SET NULL` (an unassigned
ticket is still a valid, open ticket).

### Decision 3: Default value — `created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()` and `internal BOOLEAN NOT NULL DEFAULT FALSE`
ERD said: every `created_at` is a `timestamp`; `Comment.internal` is a `boolean`
("visible to agents only").
Schema decided: every `created_at` is `TIMESTAMPTZ NOT NULL DEFAULT NOW()`, and
`internal` is `BOOLEAN NOT NULL DEFAULT FALSE`.
Reason: `DEFAULT NOW()` means callers can never forget to set the creation time,
and `TIMESTAMPTZ` (not `TIMESTAMP`) stores an absolute instant regardless of server
timezone. The broken schema stored `internal` as `TEXT DEFAULT 'false'`, which
allows garbage values and string/boolean confusion; a real `BOOLEAN` defaulting to
`FALSE` means a new comment is public unless explicitly marked internal.

## Rejected Table Shape

### Shape: `tickets.tags TEXT[]` (tags stored as an array column on the ticket)
What it was: the broken schema ran `ALTER TABLE tickets ADD COLUMN tags TEXT[]`,
storing each ticket's tags as a Postgres text array directly on the ticket row.
Why rejected: it collapses a many-to-many relationship into a denormalized array.
It cannot reference the real `Tag` entity (so there is no shared tag identity,
`org_id`, or `color_hex`), it cannot store the per-association metadata the ERD
requires on `TicketTag` (`added_by`, `added_at`), and it has no referential
integrity — a tag name in the array can be misspelled or orphaned with nothing
stopping it.
What would break: renaming or deleting a tag can't propagate (you would have to
rewrite every array), you can't answer "who tagged this ticket and when", you can't
enforce "a tag belongs to an org", and "find all tickets with tag X" becomes an
array scan instead of an indexed join. The correct shape is the `tags` entity plus
a `ticket_tags` join table (`ticket_id`, `tag_id`, `added_by`, `added_at`) that
resolves the M:N and carries its own attributes.

## Running the tests
The provided `tests/schema.test.sql` is used **unchanged** (nothing in this
submission touches `tests/`):
```bash
npm install
npm run db:reset   # drops & recreates helpdesk_test, runs the migration
npm test           # all pgTAP assertions in tests/schema.test.sql pass
```

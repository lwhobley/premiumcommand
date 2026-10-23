# CUTX Premium Command

Premium hospitality operations for event execution: events, lifecycle, readiness, dispatch, suites, staffing, BEOs, banquet and culinary handoffs, inspections, communications, and closeout. Built to work for any venue; CUTX is the first.

Initial venue configuration: **26 luxury suites available for service**. Individual suite names and locations remain unset until provided by the venue. See `docs/VENUE_CONFIGURATION.md`.

The initial venue has three confirmed banquet areas: Main Arena Floor, Premium Level Lounge, and a two-room Meeting Rooms group. Their supplied areas, guest capacities, and lounge bar detail are recorded in `docs/VENUE_CONFIGURATION.md` and migration `0013_banquet_area_facts.sql`.

## Status

| Area | State |
|---|---|
| Navigation shell (13 sections, role-gated, adaptive sidebar / bottom bar) | Built |
| Sign-in (Supabase email and password; demo roles only without a backend) | Built |
| Event calendar, event list, creation, lifecycle (client rules + `transition_event`) | Built |
| Readiness from real task records (per department and overall) | Built |
| Event task generation from templates | Built |
| Live service dispatch (create, assign, accept, start, complete, block, reject, cancel; escalation) | Built |
| My Shift (requests named to you or your departments) | Built |
| Premium Spaces (suite states, attendant, dietary notes) | Built |
| Staff Deployment (roster, uncovered positions, CSV import, briefings and acknowledgments) | Built |
| BEO Management (immutable revisions, approval, flagging, department acknowledgment) | Built |
| Banquets & Culinary (timeline with dependencies, batches with ready / collected / delivered / received, menu) | Built |
| Inspections & Checklists (templates, failures open corrective tasks, approval) | Built |
| Communications (announcements to rostered staff, notifications, incident reports) | Built |
| Event Closeout & Reports (recap, manager and director sign-off, PDF, trends) | Built |
| Administration (suites, checklist library) | Built (partial: see below) |
| Meeting Notes (administrators; Claude finds the event and proposes changes, applied after review) | Built |
| BEO and menu import (administrators; Claude reads a PDF, photo, or pasted text into the BEO editor or menu) | Built |
| Premium spaces on the map: 29 suites, 2 premium clubs, and the arena floor; renamable by administrators | Built |
| Offline queue for dispatch and task updates, with conflict review | Built |
| Offline read cache for dispatch | Built |
| Security hardening for tenant links and workflow rules | Prepared in migrations `0015`–`0017`; database validation pending |
| Deployment guide and CI | See `docs/DEPLOYMENT.md`, `.github/workflows/ci.yml` |

Not yet built, or built only partly: see `docs/SECURITY_REVIEW.md` "Open" for the gaps that matter before go-live.

## Run

Demo mode (no backend, sample data):

```bash
flutter run
```

Connected to Supabase (publishable key only, never the service-role key):

```bash
flutter run --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable key>
```

## Test

```bash
flutter analyze
flutter test
```

Edge Function checks use the root `deno.json`, which keeps npm dependencies in
Deno's global cache and permits versioned `npm:` and `jsr:` imports used by the
deployable Supabase entry points. All other recommended lint rules remain enabled.

```bash
deno lint supabase/functions
deno check --no-lock supabase/functions/*/index.ts
deno test --no-lock supabase/functions/
```

Covered by tests: lifecycle rules, readiness, permissions, dispatch rules, the suite state machine, roster parsing, BEO content, failure classification, the offline outbox, responsive layouts at phone and desktop widths, and tap-target accessibility.

The database rules are covered by rolled-back SQL checks run against the live project during development. They are not yet an automated suite in CI.

## Layout

- `lib/app` — router, navigation sections, shell
- `lib/core` — config, errors, permissions, theme, offline outbox and cache, shared widgets
- `lib/features/auth` — session and auth
- `lib/features/events` — event lifecycle, readiness, calendar, workspace
- `lib/features/dispatch` — service requests, My Shift
- `lib/features/suites` — Premium Spaces
- `lib/features/staffing` — roster and briefings
- `lib/features/beo` — BEO revisions and acknowledgments
- `lib/features/operations` — banquet timeline, culinary, inspections, communications
- `lib/features/closeout` — recap, sign-off, PDF
- `lib/features/sync` — offline queue, sync banner
- `lib/features/admin` — administration
- `lib/features/meeting_notes` — meeting notes, assistant review, and the event's notes card
- `lib/features/document_import` — BEO and menu import with the document assistant
- `supabase/functions/meeting-notes-ai` — the meeting notes assistant (Anthropic API)
- `supabase/functions/document-ai` — reads BEOs and menus (Anthropic API)
- `supabase/migrations` — schema, RLS, state-machine functions, audit, performance fixes
- `docs` — deployment guide and security review

## Design notes

- The database is authoritative. Client-side rules exist to explain a refusal before a call is made.
- Workflow state changes only through database functions. Clients cannot write those columns directly.
- Readiness is computed from task records. Nothing is entered as a percentage.
- BEO revisions are never edited in place. Approval supersedes the old revision and flags affected tasks.
- Offline writes carry a client id and the version they were made against. A conflict is kept for review, never applied over someone else's change.
- Demo sign-in is hidden whenever a backend is configured.
- The meeting notes assistant only proposes. An administrator reviews each change, and `apply_meeting_note` checks and applies the accepted ones in one transaction.

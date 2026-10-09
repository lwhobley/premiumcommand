# CUTX Premium Command

Premium hospitality operations for event execution: events, lifecycle, readiness, dispatch, suites, staffing, BEOs, banquet and culinary handoffs, inspections, communications, and closeout. Built to work for any venue; CUTX is the first.

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
| Offline queue for dispatch and task updates, with conflict review | Built |
| Offline read cache for dispatch | Built |
| Security and performance review | See `docs/SECURITY_REVIEW.md` |
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
- `supabase/migrations` — schema, RLS, state-machine functions, audit, performance fixes
- `docs` — deployment guide and security review

## Design notes

- The database is authoritative. Client-side rules exist to explain a refusal before a call is made.
- Workflow state changes only through database functions. Clients cannot write those columns directly.
- Readiness is computed from task records. Nothing is entered as a percentage.
- BEO revisions are never edited in place. Approval supersedes the old revision and flags affected tasks.
- Offline writes carry a client id and the version they were made against. A conflict is kept for review, never applied over someone else's change.
- Demo sign-in is hidden whenever a backend is configured.

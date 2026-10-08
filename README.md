# CUTX Premium Command

Premium hospitality operations app for event execution: events, lifecycle, readiness, and live service.
Phase 1 (foundation) is in place. Later phases are listed as placeholders in the navigation.

## Status

| Area | State |
|---|---|
| Navigation shell (13 sections, role-gated, adaptive sidebar / bottom bar) | Built |
| Sign-in (Supabase email/password; demo roles without a backend) | Built |
| Event calendar, event list, event creation | Built |
| Event lifecycle (client rules + `transition_event` database function) | Built |
| Readiness from real task records (per department and overall) | Built |
| Command Center dashboard | Built (Phase 1 subset) |
| Live service dispatch (create, assign, accept, start, complete, block, reject, cancel; escalation) | Built |
| My Shift (requests named to you or your departments) | Built |
| Database schema, RLS, lifecycle function | Migrations `0001_foundation.sql`, `0002_service_dispatch.sql` |
| BEOs, suites, staffing, event task generation, inspections, communications, closeout | Not built (Phases 2–4) |
| Offline sync, push notifications, PDF export | Not built |

## Run

Demo mode (no backend, sample data):

```bash
flutter run
```

Connected to the Supabase project (publishable key only, never the service-role key):

```bash
flutter run --dart-define=SUPABASE_URL=https://tloxfuuzyadgkaejfhzx.supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable key>
```

## Test

```bash
flutter analyze
flutter test
```

Covered by tests: lifecycle transition rules, readiness calculation, role-to-permission mapping, and the demo repository.
Not covered by tests yet: RLS and cross-tenant isolation (needs a database test harness), and the Supabase repositories against a live project.

## Layout

- `lib/app` — router, navigation sections, shell, theme entry point
- `lib/core` — config, errors, permissions, theme, shared widgets
- `lib/features/auth` — session, auth repositories
- `lib/features/events` — event domain (lifecycle, readiness), repositories, screens
- `lib/features/command_center` — dashboard
- `supabase/migrations` — database schema, RLS policies, lifecycle function

## Design notes

- The database is authoritative. Client-side permission and lifecycle checks only exist to explain a denial before a call is made.
- Event status is changed only through `transition_event`; direct status updates are revoked for client roles.
- Readiness is computed from required task records. Nothing is entered as a percentage.
- Demo sign-in is hidden when Supabase is configured.

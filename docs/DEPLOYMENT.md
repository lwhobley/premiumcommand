# Deployment guide

This guide covers preparing CUTX Premium Command for a real venue. Steps marked **(manual)** need a person with access to the Supabase project or the hosting account.

## 1. Database

Migrations live in `supabase/migrations/` and must be applied in order:

1. `0001_foundation.sql`: tenancy, roles, permissions, events, RLS, lifecycle function
2. `0002_service_dispatch.sql`: service requests and the guarded state machine
3. `0003_planning_staffing_beo.sql`: task templates, suites, staffing, briefings, BEO revisions
4. `0004_hospitality_operations.sql`: banquet timeline, culinary handoffs, inspections, communications, closeout
5. `0005_audit_and_hardening.sql`: workflow audit trail
6. `0006_performance_policies.sql`: RLS initplan fixes, split write policies, indexes
7. `0007_close_open_items.sql`: department membership, task status function, BEO notifications, escalation rules, evidence storage
8. `0008`: the null-safe assignee check (applied as `fix_null_assignee_check`; included in `0007` in the repo)

After applying, run `supabase/tests/rls_and_rules.sql` against the database to confirm the rules hold.

Apply with the Supabase CLI against the linked project **(manual)**:

```bash
supabase link --project-ref <project-ref>
supabase db push
```

Verify after each migration with the Supabase security and performance advisors.

## 2. Users and venue access

Users are created in Supabase Auth. Then, for each person, insert:

- one `venue_memberships` row (`status = 'active'`)
- one `role_assignments` row per role

Do this with the service role in the Supabase SQL editor **(manual)**. The service-role key must never be placed in the app or in this repository.

## 3. Build configuration

The app reads two values at build time. Use the project's publishable key only:

```bash
flutter build web \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable key>
```

Without these values the app runs in demo mode with sample data. Demo sign-in is hidden when a backend is configured.

## 4. Hosting

The web build output is in `build/web/`. Any static host works. Host it on HTTPS only, since the app signs users in. **(manual: choose the host and domain)**

## 5. Mobile builds

Android and iOS folders are generated. Signing keys, store listings, and push-notification setup are not configured **(manual)**. Push notifications are not implemented yet; in-app notifications are.

## 6. Before go-live

- Run `flutter analyze` and `flutter test`.
- Apply all migrations, then run both advisors.
- Confirm RLS with two test accounts at two venues. Each should see only its own venue.
- Confirm demo roles do not appear on the sign-in screen.
- Confirm the audit log records a test workflow change.

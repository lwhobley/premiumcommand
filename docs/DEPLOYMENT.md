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
8. `0008_people_admin.sql`: people and access administration
9. `0009_review_fixes.sql`: membership and workflow corrections
10. `0010_push_notifications.sql`: device tokens and push outbox trigger
11. `0011_floor_plan_studio.sql` through `0014_banquet_area_event_links.sql`: floor plans, suite count, banquet areas, and event links
12. `0015_tenant_relationships_and_inspection_creation.sql`: tenant-safe references and inspection creation rules
13. `0016_workflow_guards.sql`: state-machine insertion guards, sign-off separation, director continuity, and private member names
14. `0017_push_environment_configuration.sql`: project-specific push endpoint
15. `0018_idempotent_offline_actions.sql`: retry-safe dispatch and task actions with task version checks
16. `0019_session_bound_push_tokens.sql`: push tokens tied to live Auth sessions

Migration `0015` rejects existing rows with cross-venue references. Migration `0016` can reject closeouts already signed by the same person in both roles. Investigate and correct these rows before retrying. After applying, run every rolled-back script in `supabase/tests/` against that database. A local PostgreSQL server is required for these checks; Flutter tests do not execute SQL migrations.

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

The web build output is in `build/web/`. Serve the included `three/` directory with the build: the Floor Plan Studio uses local Three.js modules and 3D models there. Host it on HTTPS only, since the app signs users in. **(manual: choose the host and domain)**

## 5. Mobile builds

Android and iOS folders are generated. Signing keys and store listings are not configured **(manual)**.

Push delivery requires the `send-push` Edge Function and Firebase credentials **(manual)**. The checked-in `supabase/config.toml` disables the platform JWT check for this function because the database webhook authenticates with its own private `x-push-secret`; the function rejects calls without that secret. [Supabase documents this configuration](https://supabase.com/docs/guides/functions/function-configuration).

For each Supabase environment, deploy that function with its own `FIREBASE_SERVICE_ACCOUNT` and `FIREBASE_PROJECT_ID` secrets. In that environment's SQL editor, set `app_private.push_config.endpoint_url` to the **verified HTTPS URL of that same project's** `send-push` function:

```sql
update app_private.push_config
   set endpoint_url = '<verified same-project send-push URL>'
 where id = 1;
```

Leave it null to disable pushes. Do not copy a production URL into staging or local configuration. Confirm a notification reaches a real device and inspect the function and database logs before marking push delivery verified.

## 6. Before go-live

- Run `flutter analyze` and `flutter test`.
- Apply all migrations, then run both advisors.
- Confirm RLS with two test accounts at two venues. Each should see only its own venue.
- Confirm demo roles do not appear on the sign-in screen.
- Confirm the audit log records a test workflow change.

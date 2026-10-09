# Security and performance review

Reviewed against the Supabase advisors on the Premium Command project after migration `0006`, and against the rules in the database migrations.

## Checked

| Area | Result |
|---|---|
| Anonymous access to RPC functions | None. Every write function is revoked from `anon` and `public`. |
| Signed-in access to security-definer functions | Intentional. These are the RPC entry points, plus helpers that RLS calls (`is_venue_member`, `has_permission`). The advisor flags them and they cannot be avoided. |
| Direct status writes | Revoked for events, service requests, suite state, culinary batches, BEO revisions, timeline status, closeouts, and inspections. Changes go through the functions. |
| Cross-tenant reads | Every venue-scoped table has an RLS policy based on membership. A rolled-back test confirmed a member of one venue cannot see another venue's event. |
| Service-role key in the app | None. The client only reads `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` from build-time defines. |
| Demo bypass | Demo sign-in is shown only when no backend is configured. |
| Revision immutability | BEO revisions have no client insert, update, or delete grant. Approval supersedes by status, never by overwrite. |
| Audit trail | Triggers record status and state changes for service requests, BEO revisions, suites, culinary batches, timeline items, inspections, and closeouts. Free-text content is not copied. |
| Performance | `auth.uid()` evaluated once per statement. Write policies split per command. Indexes added on hot foreign keys. |

## Accepted

- **Unused-index and unindexed-foreign-key notices** (INFO). The project is new and has little data. Indexes were added only where a hot query needs them.
- **Authenticated-callable definer functions.** Intended. Each one checks membership and permission before acting.

## Open

These are real gaps. They are not fixed yet.

1. **Department-level acceptance is not checked against department membership.** Any staff member with `manage_requests` can accept or work a request assigned only to a department. A suite attendant could act on a banquet request. Fix: store department membership per user and check it in `transition_service_request`.
2. **Task status changes are not validated on the server.** A holder of `update_tasks` can set any status directly. Only completion is tracked. Fix: move task status into a function with the same rules as the other state machines.
3. **Notifications for BEO revisions** are not sent. Only announcements notify people. Approval flags the work but tells no one.
4. **Escalation thresholds are fixed in the app**, not configurable per venue or category.
5. **Photo evidence** fields exist, but no file storage is wired up.
6. **Cross-tenant tests** run in one database session with rollback. They are not yet an automated suite run in CI.
7. **No push notifications.** In-app only.

Each open item needs a decision or a migration before go-live. None is hidden by the current demo behavior.

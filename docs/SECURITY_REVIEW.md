# Security and performance review

Reviewed against the Supabase advisors and the migration rules. Migration `0007` and the function fix that followed it closed the open items listed in the previous review.

An additional full review on October 14, 2026 found cross-venue child references, workflow insert bypasses, shared-device cache leaks, and offline retry risks. Migrations `0015`–`0020` and the client changes address those findings. They were applied to the Premium Command Supabase project on October 14, 2026 and the rolled-back SQL checks completed without errors. A real-device push test remains open.

## Checked

| Area | Result |
|---|---|
| Anonymous access to RPC functions | None. Every write function is revoked from `anon` and `public`. |
| Signed-in access to security-definer functions | Intentional. These are the RPC entry points, plus helpers that RLS calls (`is_venue_member`, `has_permission`, `in_department`). The advisor flags them and they cannot be avoided. |
| Direct status writes | Revoked. Events, service requests, suite state, culinary batches, BEO revisions, timeline status, closeouts, inspections, and task rows all change only through functions. |
| Cross-tenant reads | Every venue-scoped table has an RLS policy based on membership. `supabase/tests/rls_and_rules.sql` checks that a member of one venue cannot see another venue's event. |
| Department-level work | Only people in the request's department can accept, start, complete, block, or reject a department-level request. Managers can reassign. |
| Task status | Set through the version-checked `set_task_status_once` RPC. Reopening needs a manager. A task flagged by a BEO revision cannot be completed until its department acknowledges the revision. |
| BEO revisions | Immutable. Approval supersedes the old revision and notifies everyone whose department changed. |
| Audit trail | Triggers record status and state changes for service requests, BEO revisions, suites, culinary batches, timeline items, inspections, and closeouts. Free-text content is not copied. |
| Evidence photos | Private `evidence` bucket. Read and write are limited to members of the venue that owns the path. Files are capped at 5 MB and limited to JPEG, PNG, or WebP. Viewing uses short-lived signed links. |
| Meeting notes and the assistant | Drafts and proposals are readable only by administrators. Applied notes become part of the event and are readable by venue members. Applied notes cannot be edited or deleted. `apply_meeting_note` re-checks administrator and event permissions, validates every change, applies them in one transaction, and writes an audit entry with the change types only. `supabase/tests/meeting_notes.sql` covers these rules. |
| Data sent to Anthropic | When an administrator asks the assistant, the `meeting-notes-ai` function sends the note text and the venue's event list (names, types, times, guest counts, managers) to the Anthropic API. For the matched event it also sends its notes, tasks, menu, and suite guest contacts and dietary notes. Nothing is sent unless an administrator asks. The API key is a function secret. |
| Service-role key in the app | None. The client reads only `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` from build-time defines. |
| Demo bypass | Demo sign-in is shown only when no backend is configured. |
| Performance | `auth.uid()` evaluated once per statement. Write policies split per command. Indexes added on hot foreign keys. |

## Defects found and fixed in this round

- **Department check silently passed.** `transition_service_request` compared `assigned_user_id = auth.uid()` directly. For a department-level request that comparison is NULL, and `NULL OR false` is NULL, so the `IF NOT ...` check did not raise. Any operator could act on another department's request. Fixed with `coalesce` in migration `0007`, and the rule test now catches it.

## Accepted

- **Unused-index and unindexed-foreign-key notices** (INFO). The project is new and has little data.
- **Authenticated-callable definer functions.** Intended. Each write entry point checks membership and permission before acting.

## Still open

1. **Push notifications are built but unverified on a device.** Devices register a token (`device_tokens`), and a trigger on `notifications` queues a call to the `send-push` Edge Function. Migration `0017` requires each environment to configure its own verified function URL; delivery also requires a deployed function, Firebase credentials, and a real device test. Web push is not included.
2. **Department membership has no admin screen.** It is stored and enforced, but people are assigned by SQL (or the Supabase dashboard) for now. The admin screen needs a user directory, which the app does not have yet.
3. **Escalation limits are configured per venue, not per category.** Category-level thresholds would need a second dimension in `escalation_rules`.
4. **The isolation checks are a script, not a CI job.** `supabase/tests/rls_and_rules.sql` runs against a database with the migrations applied. CI has no database credentials, so it does not run there.
5. **Other venue configuration is not built.** Event types, department names, and service-level targets are fixed in code.

Each of these is a decision or a missing credential, not a hidden risk in the current behavior.

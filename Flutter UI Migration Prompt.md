# Prompt: apply the Broadsheet UI to CUTX Premium Command (Flutter)

Restyle the whole Flutter app in `lib/` to match the approved prototype `CUTX Premium Command.dc.html` and the Broadsheet design system. This is a visual change only. Do not change routing, providers, repositories, permissions, offline logic, or database behavior. Keep every existing screen, section, and role gate in `AppSection`.

## 1. Theme: replace `lib/core/theme/app_theme.dart`

Replace the brass and warm-neutral palette with these tokens.

### Colors (`AppColors`)

* `background` #F3F2F2 (paper), `surface` #EAE9E9, `text` #201E1D
* `divider` = text at 16% opacity
* `accent` #0088B0 (interactive, cyan), `accent600` #1186AC (hover), `accent700` #006786 (pressed, and accent text at paragraph size), `accent100` #E9F8FF, `accent200` #CBEEFF, `accent800` #004961
* `accent2` #D6006C (magenta, rare), `accent2100` #FFF1F4, `accent2700` #AA0B56, `accent2800` #790E3D
* Neutral ramp: 100 #F8F4F4, 200 #EAE7E7, 300 #D7D3D3, 400 #BAB6B6, 500 #9B9797, 600 #7D7979, 700 #605D5D, 800 #444141, 900 #2D2B2B
* `muted` = neutral700 (#605D5D). Use it for secondary text.

Semantic status mapping. Use only the two accents and neutrals. Pair every color with a text label.

* ready, in service, in progress, accepted: accent tag (bg accent100, fg accent800)
* blocked, delayed, urgent, escalated, uncovered, overdue, failed: accent2 (tag bg accent2100, fg accent2800; standalone text accent2700)
* everything else (draft, planning, not started, closed, low, normal): neutral tag (bg #E3E0E0, fg neutral800)
* Remove the `ready/inProgress/attention/delayed/blocked` greens, blues and oranges. Update `readinessColor` and `eventStatusColor` in `core/widgets/status_chip.dart` to return these three tones.

### Type

Source Serif 4 only, weights 400 and 600 plus true italic. Bundle it in `assets/fonts` (or use `google_fonts`) and set `fontFamily` globally. Remove NotoSans as the UI font; keep it only as a PDF fallback if the PDF code needs it. No sans-serif anywhere in the UI.

* Screen title: 34 / 1.05, w600, letter-spacing -0.02em
* Section heading: 20, w600
* Row title: 17 to 19, w600
* Body: 15 / 1.55
* Meta and labels: 13, muted
* Kicker: 11, uppercase, letter-spacing 0.1em, accent700
* Tag text: 11

### Shape and space

Radius 2 everywhere (4 for sheets and dialogs). Spacing scale 5 / 10 / 15 / 20 / 30 / 40. Screen horizontal padding 24. Minimum tap target 44.

### Elevation

Use shadow only for bottom sheets and dialogs: `0 12 32` at ink 22%. Nothing else floats.

### Phosphor duotone icons

Add `phosphor_flutter` and use `PhosphorIconsDuotone.*` throughout. Replace every `Icons.*`. In `AppSection`, change `icon` to a `PhosphorIconData` (squaresFour, calendarBlank, fileText, door, tag, forkKnife, usersThree, lightning, identificationBadge, listChecks, megaphone, chatCircleText, clipboardText, notePencil, gear, cube).

## 2. ThemeData wiring

* `scaffoldBackgroundColor` and `canvasColor`: background.
* `AppBar`: transparent, no elevation, left-aligned, no title bar. Screens render their own large serif title at the top of the scroll content (kicker above, title below).
* `FilledButton`: accent fill, bg-colored text, min height 48, radius 2, w600 15px. Hover and pressed use accent600 and accent700 through `WidgetStateProperty`.
* `OutlinedButton`: transparent, 1px divider border, ink text. Hover and pressed fill ink at 7% and 14%.
* `TextButton`: accent text, hover tint accent at 10%.
* `Input`: surface fill, 1px divider border, radius 2, focused border accent, hint at 65% ink. Min height 44.
* `SegmentedButton`: radius 2, selected fill accent with bg-colored text, 1px divider border, no checkmark, `softWrap: false`.
* `Chip/FilterChip`: radius 2, selected fill accent.
* `NavigationBar`: bg color, 83 high, no indicator pill, no surface tint. Selected icon and label accent, unselected muted. A top hairline at 12% ink is the one allowed rule. Labels w600 11. Keep the existing 4 primary tabs plus More. The Dispatch tab shows a magenta count badge for escalated requests.
* `Dialog` and `BottomSheet`: surface fill, radius 4 (top corners for sheets), the elevation above, 40x4 drag handle in neutral400.
* Focus: 2px accent outline, offset 2. Disabled: 45% opacity.
* Tag widget: new `Tag(label, tone)` replacing `StatusChip`. Radius 2, padding 10x3, no border, bg and fg from the tone table above.

## 3. Layout rules for every screen

1. Remove `Card` borders and outlines. `cardTheme` becomes surface fill, radius 2, no border, no elevation. Use `Card` only for discrete items that need a box (a listing, a sheet). Everywhere else use open rows: no `Card`, no `Divider`, no `ListTile` separators. Separate sections with whitespace (30 to 34 between sections, 12 to 16 between rows).
2. Flush-left, asymmetric. Headings left aligned. No centered text except the PIN keypad digits.
3. Every screen starts with kicker, large title, and an optional one-line muted subtitle. Back navigation is an accent text button with a Phosphor caret, not an AppBar arrow.
4. Metrics are large serif numerals (46, w600) with a muted 13px label beneath, in a 2-column grid, no boxes. Alert values use accent2.
5. One accent per small component. Cyan for interactive elements, magenta only for alerts.
6. Progress and readiness use a 5px bar (track neutral300, fill accent, accent2 under 50%, neutral600 in between). No percentage text color other than those.
7. Tonal fills at 100 to 300 for selected or hovered states. Never use alpha-muted text below 4.5:1 contrast.

## 4. Screen-by-screen

Apply the prototype's layout to each screen. File paths in parentheses.

* Sign in (`auth/presentation/sign_in_screen.dart`): CUTX Event Center logo (`assets/images/cutx_event_center_logo.png`, 132 wide), kicker "Premium hospitality operations", title "CUTX Premium Command", subtitle with venue. Segmented Staff PIN / Admin email. PIN as four dots plus a 3x4 keypad of 56-high surface keys (serif 24, w600, backspace key). Error text in accent2700. Demo roles as full-width outlined rows when no backend.
* Command Center (`command_center/*`): 2x2 numerals, a "Premium level" block with a single-row bar of one cell per suite colored by state (tap opens Premium Spaces), then "Active now" and "Upcoming" as open event rows: name (18, w600) with a Tag at right, meta line, department readiness as small Tags.
* Event Calendar / Event Workspace / Event detail (`events/presentation/*`): open rows. Detail has kicker (event type), title, status Tag, a two-column label/value grid, readiness bars per department, an overdue and blocked line, a primary "Move to <next status>" button gated by permission, and outlined shortcuts to BEO, Suites, Dispatch.
* Live Service Dispatch / My Shift (`dispatch/presentation/*`): segmented Open / All, priority Tag, status and age line in muted (accent2700 when escalated or blocked), a primary action button (Accept, Start, Complete, Resume) plus outlined Block. New request is a bottom sheet: category chips, location select, priority segmented, description field. My Shift adds clock in/out, briefing acknowledgment, and "Requests for me".
* Premium Spaces (`suites/presentation/*`): 5-column grid of 56-high suite tiles filled by state (not started neutral300, setup accent300, ready accent, in service accent700, closing accent2300, closed neutral400), a legend, a "Clubs and floor" list, and a bottom sheet with attendant, runner, dietary notes, and the next-state button. Keep the 3D map and floor plan views as they are, only restyle their chrome.
* BEO Management, Banquets & Culinary, Inspections, Communications, Chat, Closeout, Staff Deployment, Staff Management, Meeting Notes, Sales, Administration, Floor Plan Studio: same open-row pattern. Inspections use Pass/Fail segmented controls (Fail fills accent2). Staff Deployment shows uncovered positions in accent2700 with an Assign button for managers. Chat bubbles: surface for others, accent200 for mine, radius 2, name and time in 11px muted.
* More (`app/more_screen.dart`): 24px Phosphor icon in accent700, 18px serif label, caret, 56-high rows with no dividers. Sign out as an outlined button.
* Sync banner (`sync/presentation/sync_banner.dart`): accent100 fill for syncing, accent2100 with accent2800 text for conflicts. No colored icons.
* Wide layout (`shell_scaffold.dart` sidebar): keep the 240 sidebar, bg color, serif brand at top, selected item accent100 fill with ink text, no divider lines. Phosphor icons.

## 5. Cleanup and checks

* Delete unused color constants and any hard-coded `Color(0x...)` in feature files. Every color comes from `AppColors`.
* Replace any `FontWeight.w700` with w600. Only w400 and w600 are loaded.
* PDF output (`recap_pdf.dart`, `floor_plan_pdf.dart`) can use the same palette and Source Serif 4, but this is optional.
* Run `flutter analyze` and `flutter test`. Update `responsive_and_accessibility_test.dart` if tap-target or contrast assertions reference the old palette. All tap targets stay at 44 or more.
* Verify at phone width (390) and desktop width (1200). Check that no segmented control or tag label wraps (`softWrap: false`, `maxLines: 1`).
* Acceptance: no green, orange, or brass anywhere; no sans-serif; no card borders; no `Divider` between sections; every status carries a text label.

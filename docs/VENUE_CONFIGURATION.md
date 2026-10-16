# Initial venue facts

The Premium Department at Credit Union of Texas Event Center in Allen, Texas has **26 luxury suites available for service**. This count was supplied by the venue operator on October 14, 2026.

On October 15, 2026 the operator supplied the labeled premium-level plan (`Suites Labeled.pdf`). It identifies **29 suites, numbered 201 through 229**, and the operator confirmed that all 29 are available for service, replacing the earlier count of 26. Suite capacities, locations, and service zones have still not been supplied; leave them blank rather than inferring them from the plan.

Migration `0022_premium_suites_and_orders.sql` creates `Suite 201` through `Suite 229` for the initial venue (identified the same way as migrations `0012` and `0021`) and changes the service count from 26 to 29 unless an operator already set a different value.

### Premium level map and suite orders

Premium Spaces shows a clickable 3D map of the premium level for the selected event. The suite outlines in `lib/features/suites/domain/premium_level_layout.dart` were traced from the plan's vector drawing. The plan has no scale bar, so the map is proportional, not measured, and the seating bowl is illustrative. Suites are matched to the map by the number in their name (`Suite 204` → 204). Colors show each suite's order status for the event; suites not assigned to the event are greyed out.

Tapping a suite opens its panel: suite state, the suite's order, and a link to the event's BEO. Managers (`manage_events`) can add the suite to the event, edit the order (items, quantities, delivery time, notes), and confirm it. Suite staff (`update_tasks`) mark a confirmed order delivered. Editing a confirmed order returns it to draft until it is confirmed again, and delivered orders cannot be changed. Orders are stored in `suite_orders`, one per suite assignment, and are written only through `save_suite_order` and `set_suite_order_status`.

The map page is `web/three/suite_map.html`. It runs in an iframe on web and in a WebView (`webview_flutter`) on iOS and Android. Its script, `web/three/suite_map.js`, is built from `tool/suite_map/scene.js`; the build command is at the top of that file.

Migration `0012_service_suite_count.sql` adds a venue-level count and sets it to 26 if exactly one existing venue is named `Credit Union of Texas Event Center` or `CUTX Event Center`. If that venue has not been created yet, or if the name is ambiguous, set the count to 26 in Administration after identifying the right venue. Administrators can change the count later without changing other venues.

### Premium clubs

On October 16, 2026 the operator identified the two open ends of the premium level as premium clubs: one between suites 229 and 201, the other between suites 215 and 216. The supplied plan does not draw them, so their map outlines in `premium_level_layout.dart` fill the concourse between the arena floor's edge and the level's outer edge at each end. Like the suites, the map is proportional, not measured.

Clubs are premium spaces stored with the suites in `venue_suites`, with `map_area` set to `club_a` or `club_b` to place them on the map. They can be added to an event, move through the same setup states, take staff placements and orders, and open the same panel when tapped on the map. Migration `0030_premium_clubs.sql` adds `map_area` and creates `Premium Club A` and `Premium Club B` for the initial venue (identified as in `0022`). The club names, capacities, and service zones were not supplied; the seeded names are placeholders. Administrators can add a club under Administration by choosing its position on the map. Clubs are not counted in the suite service count.

### Arena floor as a service area

The operator also identified the arena floor as a serviceable area on the map (October 16, 2026). It is a premium space like the suites and clubs, with `map_area` set to `arena_floor`, and uses the floor outline already on the map, drawn flat at ground level. It is tappable and colored by status when it is assigned to the event. Migration `0031_arena_floor_service_area.sql` creates it for the initial venue as `Main Arena Floor`, the name the operator gave the same space as a banquet area; the banquet area profile is separate and unchanged.

## Banquet areas

The venue operator confirmed three banquet areas on October 14, 2026:

| Banquet area | Size | Guest capacity | Other confirmed details |
|---|---:|---:|---|
| Main Arena Floor | 17,000 sq ft | Up to 900 | — |
| Premium Level Lounge | 2,000 sq ft | Up to 100 | Full-service bar |
| Meeting Rooms | Not provided | Up to 32 per room | Two rooms; they can combine |

The capacity of the Meeting Rooms when combined was **not provided**. The individual room identifiers and measurements were also not provided. Do not infer a combined capacity of 64 or create floor-plan dimensions from square footage.

Migration `0013_banquet_area_facts.sql` records these as three area profiles. It creates named physical-space records only for Main Arena Floor and Premium Level Lounge. Meeting Rooms remains a group profile until both rooms are identified. As with migration `0012`, the seed runs only when the initial venue can be identified unambiguously by its supplied name. Administrators can review and edit the area profiles in Administration after the migration is applied.

Floor Plan Studio shows these area profiles as **unscaled 3D schematics** in the web app, with an isometric preview on mobile and desktop native builds. The Meeting Rooms profile can be viewed as two separate blocks or one combined block; this is a conceptual presentation, not a claim about actual geometry or combined capacity. Measured seating layouts still require entered room width and depth. Individual Meeting Room IDs, measurements, doors, and verified floor plans must be supplied before precise 3D layouts can be configured.

Suite cards open the BEO for the event to which that suite is assigned. Banquet area cards open an event link list; a manager can attach events to an area, then open or create the event's BEO from the list. These links use the existing one-BEO-per-event workflow. Migration `0014_banquet_area_event_links.sql` adds the tenant-checked association table and permission policies. Run migrations `0011` through `0014` before using the full floor-plan and BEO linking flow.

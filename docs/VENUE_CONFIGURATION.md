# Initial venue facts

The Premium Department at Credit Union of Texas Event Center in Allen, Texas has **26 luxury suites available for service**. This count was supplied by the venue operator on October 14, 2026.

The individual suite identifiers, locations, capacities, and service zones have not been supplied. Do not generate suite profiles or event assignments from the count. Add those records when the venue provides its actual suite list.

Migration `0012_service_suite_count.sql` adds a venue-level count and sets it to 26 if exactly one existing venue is named `Credit Union of Texas Event Center` or `CUTX Event Center`. If that venue has not been created yet, or if the name is ambiguous, set the count to 26 in Administration after identifying the right venue. Administrators can change the count later without changing other venues.

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

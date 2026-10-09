# Mega City — native city assembly

85 real buildings, copied from the accepted MC-01 through MC-21 packages at their original scale. Each remains a separate Model with its original KaijuHouse tag, attributes, PrimaryPart, signs and embedded runtime. Existing power/grid lightning, containment motion and cooling effects are retained. This is an assembled city for terrain sculpting, not a claim of completed Studio playtesting or game integration.

## Distribution and streets

A deterministic placement pass preserves the inventory of every building type but uses soft neighbourhood preferences and penalties for identical neighbours. Districts remain recognisable as concentrations, without hard borders. Housing, markets, hotels, utility buildings and data centres appear between the core neighbourhoods. The source district and current position are recorded separately in the placement manifest. The Kanagawa entrance sits on the seaside apron; Mega Tower stays behind the guardian plaza.

The connected street surface contains two nominal 180-stud waterfront routes, two 220-stud crossings, 64-stud local streets/collectors, individual forecourts, an inland boulevard and the guardian plaza. Routing avoids real, rotated building bounds and the six ice-column feet. A union of the road polygons is triangulated into native WedgeParts, eliminating coplanar road panels at intersections. Gradients follow the 20/40/60/80-stud terrace levels. The complete city deliberately remains a large layout: actual largest-Kaiju traversal, street widths, bridges and camera still require Studio review.

## Studio / terrain workflow

Stop the prior Rojo server. On `feat/mega-city-harbor-gate`, run:

```sh
git pull --ff-only
rojo serve mega-city-final.project.json
```

Use port 34873. The standard `default.project.json` also opens this city, on port 34872. The older per-building and blockout projects remain available. No Python build step or runtime installer is needed to use the committed city.

Select `Workspace.MegaCity` and press **F**. The previous `MegaCityBlockout` and optional `MegaCityIceCeiling` models are explicitly emptied by this configuration so their proxies do not overlap the real city. Unknown Workspace objects and the native Terrain instance are preserved. If the place also contains older individual review buildings, remove those review copies separately.

Editable groups:

- **Buildings:** 85 native building Models, already positioned in edit mode.
- **RoadNetwork:** connected pavement, shoulders and sparse lane marks.
- **RiftDetails:** fractured fjord ice, ledges, hanging ice, deep thermal glows, native Smoke fog/steam emitters and a dark visual floor.
- **TerrainGuides:** cyan rift rim, green coastline and amber depth lines. These are non-colliding construction aids; the rim follows the current terrace height. The suggested dark floor is near Y=-900; sea level is approximately Y=-4.
- **TerrainProxy:** temporary rock/snow shelves, arrival platform, ice walls, ice columns and bridge underdecks. These support the draft before terrain is carved. Replace the landscape portions with Terrain as desired; retain bridge underdecks and columns if useful.

Carve the inlet and chasm between the cyan lines and the sea along the green coast guide. Keep sufficient rock under roads and building foundations. Place actual Terrain water at the chosen sea level, ending in broken ice before the inland chasm. Remove or hide `TerrainGuides` once finished. Remove/replace the corresponding `TerrainProxy` landscape pieces after sculpting; preserve the pieces you still want as structures. Final terrain texture, ice cave ceiling, lighting and sea water are artist-authored in Studio. The old magenta elevated-rail planning guide is not included as a finished railway.

Smoke and existing building animations should be reviewed in Play. The deep glows are sparse, not a continuous lava river. The dark floor can be covered/replaced with sculpted rock. No Guardian character is included.

## Rebuild / verification

`python -m pip install 'shapely>=2.1'` then `python tools/build_mega_city_final.py` rebuilds the city from source models. `python tools/validate_mega_city_final.py` checks native exports and manifest. `python tools/render_mega_city_final_plan.py` renders the SVG using Matplotlib.

The generator validates inventory, footprint separation, column clearance, connected road surfaces and road/building separation. The native validator checks source-part preservation, transformed bounds, unique referents, PrimaryParts, anchored geometry, finite positive dimensions (maximum 2048 studs), orthonormal transforms, scripts, signage and Rojo paths. Studio rendering, Smoke appearance, terrain, Kaiju navigation, city-scale performance and live game integration remain untested here. The combined native city contains tens of thousands of Parts; performance must be measured in the target place.

Exact placements: `../plans/00-mega-city-final-layout.json`. Plan: `../plans/00-mega-city-final-layout.svg`.

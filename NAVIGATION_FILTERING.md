# Ackermann Navigation Filtering Guide

## Problem Statement

Ackermann robots need to navigate only on roads wide enough for them (~0.5m vehicle width). Narrow streets, pedestrian paths, and service roads should be excluded from navigation waypoints.

## Current Approach

### 1. Strict Waypoint Filtering (Source of Truth)

The `extract_osm_waypoints.py` script filters roads based on:

**Always Navigable (Major Roads):**
- motorway, trunk, primary, secondary, tertiary
- motorway_link, trunk_link, primary_link, secondary_link, tertiary_link

**Conditionally Navigable:**
- **Residential**: Only if:
  - Width ≥ 3.5m (explicitly tagged), OR
  - Lanes ≥ 1 with estimated width ≥ 3.5m (3m per lane), OR
  - **Excluded if no width/lanes info** (often too narrow)
- **Unclassified**: Included if no width info (often wider than residential)

**Always Excluded:**
- service (parking lots, too narrow)
- footway, path, pedestrian, cycleway, track, steps

### 2. Visual Color Coding (Approximate)

**Limitation**: OSM2World assigns `ASPHALT` material to ALL roads (major and minor), so we cannot reliably distinguish navigable vs non-navigable by material name alone.

**Current Colors:**
- **Dark grey (0.15, 0.15, 0.15)**: ASPHALT/CONCRETE materials
  - Includes major roads (navigable)
  - Also includes narrow residential roads (NOT all are navigable!)
- **Light grey (0.4, 0.4, 0.4)**: PAVING_STONE/PAVING/KERB
  - Sidewalks, pedestrian areas (definitely non-navigable)

**⚠️ IMPORTANT**: Visual colors are approximate. Some dark grey roads may be too narrow for Ackermann vehicles. Always use `*_navigable.json` files as the source of truth for navigability!

### 3. Output Files

**For DRL Training (Use These!):**
- `*_navigable.json` - Waypoints for navigable roads only
- `*_navigable_lanes.json` - Navigable lanes organized by street name

**For Reference:**
- `waypoints.json` - All waypoints (includes narrow roads)
- `navigability_map.json` - Maps navigable vs non-navigable waypoints

## Best Practices

1. **Always use `*_navigable.json` files** for:
   - DRL training waypoints
   - Delivery coordinate selection
   - Task allocation

2. **Visual colors are approximate** - don't rely on Gazebo colors alone

3. **Check filtering output** - the script shows how many narrow roads were excluded

## Future Improvements

Possible enhancements:
1. Pre-filter OSM data before OSM2World (exclude narrow roads from model)
2. Post-process OBJ file to assign different materials based on navigability map
3. Use RViz markers to highlight navigable roads visually
4. Create separate Gazebo model for navigable roads overlay


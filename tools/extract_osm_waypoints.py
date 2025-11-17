#!/usr/bin/env python3
"""
Extract road centerline waypoints directly from OSM data.
More accurate than extracting from SDF meshes for DRL coordinate extraction.
"""

import xml.etree.ElementTree as ET
import json
import argparse
import math
from typing import List, Tuple, Dict
from pathlib import Path


def parse_osm_ways(osm_file: str, highway_types: List[str] = None) -> List[Dict]:
    """
    Extract road ways from OSM file.
    
    Args:
        osm_file: Path to OSM XML file
        highway_types: List of highway types to include (default: common road types)
    
    Returns:
        List of way dictionaries with nodes and metadata
    """
    if highway_types is None:
        # Only include roads suitable for Ackermann vehicles (exclude narrow paths)
        # Excluded: 'service' (too narrow, parking lots), 'footway', 'path', 'pedestrian', 'cycleway', 'track', 'steps'
        # Note: 'residential' and 'unclassified' will be filtered by width/lanes later
        highway_types = [
            'motorway', 'trunk', 'primary', 'secondary', 'tertiary',
            'unclassified', 'residential',  # Will be filtered by width later
            'motorway_link', 'trunk_link', 'primary_link', 'secondary_link', 'tertiary_link'
        ]
    
    tree = ET.parse(osm_file)
    root = tree.getroot()
    
    # First pass: collect all nodes
    nodes = {}
    for node in root.findall('node'):
        node_id = node.get('id')
        lat = float(node.get('lat'))
        lon = float(node.get('lon'))
        nodes[node_id] = (lat, lon)
    
    # Second pass: extract ways (roads)
    ways = []
    for way in root.findall('way'):
        # Check if it's a highway/road
        is_highway = False
        highway_type = None
        for tag in way.findall('tag'):
            if tag.get('k') == 'highway':
                highway_type = tag.get('v')
                if highway_type in highway_types:
                    is_highway = True
                break
        
        if is_highway:
            # Filter out non-navigable roads based on access restrictions
            # Check for access restrictions that prevent vehicle access
            access_restricted = False
            for tag in way.findall('tag'):
                k, v = tag.get('k'), tag.get('v')
                # Exclude roads with vehicle access restrictions
                if k == 'access' and v in ['no', 'private', 'permit']:
                    access_restricted = True
                if k == 'motor_vehicle' and v == 'no':
                    access_restricted = True
                if k == 'vehicle' and v == 'no':
                    access_restricted = True
            
            # Skip if access is restricted (highway type already filtered above)
            if access_restricted:
                continue
            
            # Get node references
            node_refs = [nd.get('ref') for nd in way.findall('nd')]
            # Convert to coordinates
            coords = []
            for node_id in node_refs:
                if node_id in nodes:
                    lat, lon = nodes[node_id]
                    coords.append((lat, lon))
            
            if len(coords) >= 2:  # Need at least 2 points for a way
                # Extract street/lane name and road characteristics from tags
                street_name = None
                ref_name = None
                width = None
                lanes = None
                for tag in way.findall('tag'):
                    k, v = tag.get('k'), tag.get('v')
                    if k == 'name':
                        street_name = v
                    elif k == 'ref':
                        ref_name = v
                    elif k == 'width':
                        try:
                            # Handle width in meters or feet
                            width_str = v.lower().replace('m', '').replace('ft', '').strip()
                            width_val = float(width_str)
                            # Convert feet to meters if needed
                            if 'ft' in v.lower():
                                width_val *= 0.3048
                            width = width_val
                        except:
                            pass
                    elif k == 'lanes':
                        try:
                            lanes = int(v)
                        except:
                            pass
                
                # Use name, ref, or highway_type as identifier
                lane_id = street_name or ref_name or f"{highway_type}_{way.get('id')}"
                
                ways.append({
                    'id': way.get('id'),
                    'highway_type': highway_type,
                    'street_name': street_name,
                    'ref': ref_name,
                    'lane_id': lane_id,
                    'width': width,  # Store width if available (meters)
                    'lanes': lanes,  # Store number of lanes if available
                    'coordinates': coords,
                    'num_points': len(coords)
                })
    
    return ways


def latlon_to_xy(lat: float, lon: float, origin_lat: float, origin_lon: float) -> Tuple[float, float]:
    """
    Convert lat/lon to local x/y coordinates (meters).
    Uses simple equirectangular projection (good for small areas).
    
    Args:
        lat: Latitude
        lon: Longitude
        origin_lat: Origin latitude
        origin_lon: Origin longitude
    
    Returns:
        (x, y) in meters
    """
    R = 6371000  # Earth radius in meters
    x = R * math.radians(lon - origin_lon) * math.cos(math.radians(origin_lat))
    y = R * math.radians(lat - origin_lat)
    return (x, y)


def extract_waypoints_from_ways(
    ways: List[Dict],
    spacing: float = 2.0,
    min_distance: float = 5.0
) -> Tuple[List[Tuple[float, float, float]], Dict[str, List[Tuple[float, float, float]]]]:
    """
    Extract waypoints from OSM ways with specified spacing.
    
    Args:
        ways: List of way dictionaries
        spacing: Distance between waypoints along roads (meters)
        min_distance: Minimum distance between waypoints from different roads
    
    Returns:
        Tuple of (all_waypoints, lanes_dict) where:
        - all_waypoints: List of (x, y, yaw) waypoints
        - lanes_dict: Dict mapping lane_id to list of (x, y, yaw) waypoints
    """
    if not ways:
        return [], {}
    
    # Find origin (use first way's first point)
    origin_lat, origin_lon = ways[0]['coordinates'][0]
    
    waypoints = []
    lanes_dict = {}  # Map lane_id to waypoints
    waypoint_set = set()  # For deduplication
    
    for way in ways:
        lane_id = way['lane_id']
        lane_waypoints = []
        coords = way['coordinates']
        if len(coords) < 2:
            continue
        
        # Convert to x/y
        xy_coords = [latlon_to_xy(lat, lon, origin_lat, origin_lon) for lat, lon in coords]
        
        # Generate waypoints along this way
        for i in range(len(xy_coords) - 1):
            x1, y1 = xy_coords[i]
            x2, y2 = xy_coords[i + 1]
            
            # Calculate segment length and direction
            dx = x2 - x1
            dy = y2 - y1
            seg_length = math.sqrt(dx*dx + dy*dy)
            yaw = math.atan2(dy, dx)
            
            if seg_length < 0.1:  # Skip very short segments
                continue
            
            # Generate waypoints along segment
            num_points = max(2, int(seg_length / spacing) + 1)
            for j in range(num_points):
                t = j / (num_points - 1) if num_points > 1 else 0
                x = x1 + t * dx
                y = y1 + t * dy
                
                # Round to avoid duplicates
                x_rounded = round(x, 2)
                y_rounded = round(y, 2)
                
                wp_key = (x_rounded, y_rounded)
                
                # Check minimum distance from existing waypoints
                too_close = False
                for existing_x, existing_y, _ in waypoints:
                    dist = math.sqrt((x - existing_x)**2 + (y - existing_y)**2)
                    if dist < min_distance:
                        too_close = True
                        break
                
                if not too_close and wp_key not in waypoint_set:
                    waypoint_set.add(wp_key)
                    waypoint = (x, y, yaw)
                    waypoints.append(waypoint)
                    lane_waypoints.append(waypoint)
        
        # Store lane waypoints
        if lane_waypoints:
            if lane_id not in lanes_dict:
                lanes_dict[lane_id] = []
            lanes_dict[lane_id].extend(lane_waypoints)
    
    return waypoints, lanes_dict


def main():
    parser = argparse.ArgumentParser(
        description='Extract road waypoints from OSM file for DRL coordinate extraction'
    )
    parser.add_argument('osm_file', type=str, help='Path to OSM XML file')
    parser.add_argument('-o', '--output', type=str, default='waypoints.json',
                      help='Output JSON file path')
    parser.add_argument('-n', '--num-stops', type=int, default=20,
                      help='Number of delivery stops to extract (will sample from waypoints)')
    parser.add_argument('-s', '--spacing', type=float, default=2.0,
                      help='Waypoint spacing along roads (meters)')
    parser.add_argument('-m', '--min-distance', type=float, default=5.0,
                      help='Minimum distance between waypoints (meters)')
    
    args = parser.parse_args()
    
    print(f"📖 Parsing OSM file: {args.osm_file}")
    print("   Filtering for Ackermann-navigable roads only...")
    print("   ✅ Included: motorway, trunk, primary, secondary, tertiary, unclassified, residential")
    print("   ❌ Excluded: service, footway, path, pedestrian, cycleway, track, steps")
    
    ways = parse_osm_ways(args.osm_file)
    
    # Filter only clearly non-navigable roads
    # Be permissive: include roads unless explicitly too narrow (< 2.5m) or restricted
    MIN_NAVIGABLE_WIDTH = 2.5  # meters - lower threshold to include more roads
    
    # Major roads are always navigable
    major_road_types = ['motorway', 'trunk', 'primary', 'secondary', 'tertiary',
                       'motorway_link', 'trunk_link', 'primary_link', 'secondary_link', 'tertiary_link']
    
    navigable_ways = []
    narrow_ways = []
    
    for way in ways:
        highway_type = way['highway_type']
        width = way.get('width')
        lanes = way.get('lanes')
        
        # Major roads: always navigable
        if highway_type in major_road_types:
            navigable_ways.append(way)
            continue
        
        # For residential/unclassified: be permissive - include unless explicitly too narrow
        if highway_type in ['residential', 'unclassified']:
            # Only exclude if width is explicitly too narrow (< 2.5m)
            if width is not None and width < MIN_NAVIGABLE_WIDTH:
                narrow_ways.append(way)
                way['exclusion_reason'] = f'width_too_narrow_{width}m'
            # Otherwise include (even without width info - assume navigable)
            else:
                navigable_ways.append(way)
        else:
            # Other types: include by default
            navigable_ways.append(way)
    
    ways = navigable_ways
    
    # Count by highway type
    type_counts = {}
    for way in ways:
        htype = way['highway_type']
        type_counts[htype] = type_counts.get(htype, 0) + 1
    
    print(f"✅ Found {len(ways)} navigable road ways (excluded {len(narrow_ways)} explicitly narrow roads):")
    for htype, count in sorted(type_counts.items()):
        print(f"   - {htype}: {count} segments")
    
    if narrow_ways:
        print(f"   (Excluded {len(narrow_ways)} roads with width < 2.5m)")
    
    # === 1. Extract waypoints from ALL roads (full map) ===
    print(f"🛣 Extracting waypoints from ALL roads (full map)...")
    all_ways = parse_osm_ways(args.osm_file)  # Get ALL roads (no filtering)
    all_waypoints, _ = extract_waypoints_from_ways(all_ways, spacing=args.spacing, min_distance=args.min_distance)
    
    # Save full map coordinates
    with open(args.output, 'w') as f:
        json.dump({
            'waypoints': [
                {'x': wp[0], 'y': wp[1], 'yaw': wp[2]}
                for wp in all_waypoints
            ],
            'total_waypoints': len(all_waypoints),
            'source_osm': str(args.osm_file),
            'metadata': {
                'spacing': args.spacing,
                'min_distance': args.min_distance
            }
        }, f, indent=2)
    print(f"✅ Full map coordinates: {args.output}")
    print(f"   - {len(all_waypoints)} waypoints (all roads)")
    
    # === 2. Extract waypoints from NAVIGABLE roads only ===
    print(f"🛣 Extracting waypoints from navigable roads...")
    nav_waypoints, nav_lanes_dict = extract_waypoints_from_ways(ways, spacing=args.spacing, min_distance=args.min_distance)
    print(f"✅ Generated {len(nav_waypoints)} waypoints from {len(nav_lanes_dict)} navigable lanes/streets")
    
    # Prepare navigable lanes data
    navigable_lanes_data = {}
    for lane_id, lane_waypoints in nav_lanes_dict.items():
        way_info = next((w for w in ways if w['lane_id'] == lane_id), None)
        navigable_lanes_data[lane_id] = {
            'waypoints': [
                {'x': wp[0], 'y': wp[1], 'yaw': wp[2]}
                for wp in lane_waypoints
            ],
            'highway_type': way_info['highway_type'] if way_info else 'unknown',
            'street_name': way_info.get('street_name'),
            'ref': way_info.get('ref'),
            'num_waypoints': len(lane_waypoints)
        }
    
    # Save navigable lanes (user wants just this)
    navigable_lanes_output = args.output.replace('.json', '_navigable_lanes.json')
    with open(navigable_lanes_output, 'w') as f:
        json.dump({
            'lanes': navigable_lanes_data,
            'total_lanes': len(navigable_lanes_data),
            'total_waypoints': len(nav_waypoints),
            'source_osm': str(args.osm_file),
            'metadata': {
                'spacing': args.spacing,
                'min_distance': args.min_distance,
                'road_types': list(type_counts.keys())
            }
        }, f, indent=2)
    
    print(f"✅ Navigable lanes: {navigable_lanes_output}")
    print(f"   - {len(navigable_lanes_data)} lanes, {len(nav_waypoints)} waypoints")


if __name__ == '__main__':
    main()


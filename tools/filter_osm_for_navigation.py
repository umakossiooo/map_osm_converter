#!/usr/bin/env python3
"""
Pre-filter OSM file to exclude narrow roads before OSM2World conversion.
This ensures narrow roads don't appear in the Gazebo model at all.
"""

import xml.etree.ElementTree as ET
import sys
from pathlib import Path


def filter_osm_for_navigation(input_osm: str, output_osm: str, min_width: float = 2.5):
    """
    Filter OSM file to exclude narrow roads unsuitable for Ackermann vehicles.
    
    Args:
        input_osm: Input OSM file path
        output_osm: Output OSM file path (filtered)
        min_width: Minimum road width in meters
    """
    tree = ET.parse(input_osm)
    root = tree.getroot()
    
    # Roads to exclude (narrow paths, but keep sidewalks/pedestrian areas for visual distinction)
    excluded_types = ['service', 'footway', 'path', 'cycleway', 'track', 'steps',
                     'bus_stop', 'traffic_signals', 'give_way', 'stop', 'elevator']
    # Note: 'pedestrian' and 'crossing' are kept but will be colored differently
    
    # Major roads (always included)
    major_types = ['motorway', 'trunk', 'primary', 'secondary', 'tertiary',
                   'motorway_link', 'trunk_link', 'primary_link', 'secondary_link', 'tertiary_link']
    
    ways_to_keep = set()
    ways_to_remove = set()
    
    # First pass: identify ways to keep/remove
    for way in root.findall('way'):
        way_id = way.get('id')
        highway_type = None
        
        # Get highway type
        for tag in way.findall('tag'):
            if tag.get('k') == 'highway':
                highway_type = tag.get('v')
                break
        
        if not highway_type:
            ways_to_keep.add(way_id)  # Keep non-highway ways
            continue
        
        # Exclude specific types
        if highway_type in excluded_types:
            ways_to_remove.add(way_id)
            continue
        
        # Major roads: always keep
        if highway_type in major_types:
            ways_to_keep.add(way_id)
            continue
        
        # For residential/unclassified: be permissive - include unless explicitly too narrow
        if highway_type in ['residential', 'unclassified']:
            width = None
            access_restricted = False
            
            for tag in way.findall('tag'):
                k, v = tag.get('k'), tag.get('v')
                if k == 'width':
                    try:
                        width_str = v.lower().replace('m', '').replace('ft', '').strip()
                        width_val = float(width_str)
                        if 'ft' in v.lower():
                            width_val *= 0.3048
                        width = width_val
                    except:
                        pass
                elif k == 'access' and v in ['no', 'private', 'permit']:
                    access_restricted = True
                elif k == 'motor_vehicle' and v == 'no':
                    access_restricted = True
                elif k == 'vehicle' and v == 'no':
                    access_restricted = True
            
            if access_restricted:
                ways_to_remove.add(way_id)
                continue
            
            # Only exclude if width is explicitly too narrow
            if width is not None and width < min_width:
                ways_to_remove.add(way_id)
            else:
                # Include by default (even without width info)
                ways_to_keep.add(way_id)
        else:
            # Other types: keep by default
            ways_to_keep.add(way_id)
    
    # Filter relations (but keep pedestrian areas for visual distinction)
    relations_to_remove = set()
    for relation in root.findall('relation'):
        for tag in relation.findall('tag'):
            highway_type = tag.get('v')
            if tag.get('k') == 'highway' and highway_type in excluded_types:
                relations_to_remove.add(relation.get('id'))
                break
            # Keep pedestrian/crossing relations - they'll be colored differently
    
    # Second pass: remove ways and relations
    removed_count = 0
    for way in list(root.findall('way')):
        way_id = way.get('id')
        if way_id in ways_to_remove:
            root.remove(way)
            removed_count += 1
    
    # Remove filtered relations
    for relation in list(root.findall('relation')):
        if relation.get('id') in relations_to_remove:
            root.remove(relation)
            removed_count += 1
    
    # Save filtered OSM
    tree.write(output_osm, encoding='utf-8', xml_declaration=True)
    
    print(f"✅ Filtered OSM file: {output_osm}")
    print(f"   - Removed {removed_count} narrow/non-navigable roads")
    print(f"   - Kept {len(ways_to_keep)} navigable roads")
    return True


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: python3 filter_osm_for_navigation.py <input.osm> <output.osm> [min_width]")
        print("Example: python3 filter_osm_for_navigation.py bari.osm bari_navigable.osm 3.5")
        sys.exit(1)
    
    input_file = sys.argv[1]
    output_file = sys.argv[2]
    min_width = float(sys.argv[3]) if len(sys.argv) > 3 else 3.5
    
    filter_osm_for_navigation(input_file, output_file, min_width)


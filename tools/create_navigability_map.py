#!/usr/bin/env python3
"""
Create a navigability map that tracks which roads are navigable vs non-navigable.
This can be used to color-code roads or create visual overlays in Gazebo.
"""

import json
import sys
from pathlib import Path
from typing import Dict, List, Set


def create_navigability_map(navigable_waypoints_file: str, all_waypoints_file: str, output_file: str):
    """
    Create a mapping file that identifies navigable vs non-navigable roads.
    
    Args:
        navigable_waypoints_file: Path to *_navigable.json file
        all_waypoints_file: Path to waypoints.json file (all roads)
        output_file: Output JSON file with navigability mapping
    """
    nav_path = Path(navigable_waypoints_file)
    all_path = Path(all_waypoints_file)
    
    if not nav_path.exists():
        print(f"❌ Navigable waypoints file not found: {navigable_waypoints_file}")
        return False
    
    if not all_path.exists():
        print(f"❌ All waypoints file not found: {all_waypoints_file}")
        return False
    
    # Load navigable waypoints
    with open(nav_path, 'r') as f:
        nav_data = json.load(f)
    
    # Load all waypoints
    with open(all_path, 'r') as f:
        all_data = json.load(f)
    
    # Create sets of navigable coordinates (rounded for matching)
    nav_coords = set()
    for wp in nav_data.get('waypoints', []):
        x, y = round(wp['x'], 1), round(wp['y'], 1)
        nav_coords.add((x, y))
    
    # Classify all waypoints
    navigable_wps = []
    non_navigable_wps = []
    
    for wp in all_data.get('waypoints', []):
        x, y = round(wp['x'], 1), round(wp['y'], 1)
        if (x, y) in nav_coords:
            navigable_wps.append(wp)
        else:
            non_navigable_wps.append(wp)
    
    # Create mapping file
    mapping = {
        'navigable_waypoints': navigable_wps,
        'non_navigable_waypoints': non_navigable_wps,
        'navigable_count': len(navigable_wps),
        'non_navigable_count': len(non_navigable_wps),
        'total_count': len(navigable_wps) + len(non_navigable_wps),
        'metadata': {
            'navigable_file': str(nav_path),
            'all_file': str(all_path),
            'note': 'Use navigable_waypoints for DRL training. Non-navigable are too narrow for Ackermann vehicles.'
        }
    }
    
    with open(output_file, 'w') as f:
        json.dump(mapping, f, indent=2)
    
    print(f"✅ Created navigability map: {output_file}")
    print(f"   - Navigable: {len(navigable_wps)} waypoints")
    print(f"   - Non-navigable: {len(non_navigable_wps)} waypoints")
    return True


if __name__ == '__main__':
    if len(sys.argv) < 4:
        print("Usage: python3 create_navigability_map.py <navigable_waypoints.json> <all_waypoints.json> <output_mapping.json>")
        sys.exit(1)
    
    create_navigability_map(sys.argv[1], sys.argv[2], sys.argv[3])


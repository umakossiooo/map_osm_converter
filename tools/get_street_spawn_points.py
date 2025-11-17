#!/usr/bin/env python3
"""
Extract street waypoints for robot spawning and camera positioning.
Selects waypoints that are on streets (not buildings, green areas, etc.)
"""

import json
import sys
import random
from pathlib import Path
from typing import List, Tuple


def load_waypoints(waypoints_file: str, prefer_lanes: bool = True) -> List[Tuple[float, float, float]]:
    """
    Load waypoints from JSON file.
    Prefers lanes file if available (more accurate street waypoints).
    """
    waypoints_file_path = Path(waypoints_file)
    
    # Try to load from lanes file first (more accurate - organized by street)
    if prefer_lanes:
        lanes_file = waypoints_file_path.parent / waypoints_file_path.name.replace('_waypoints.json', '_waypoints_lanes.json')
        if lanes_file.exists():
            with open(lanes_file, 'r') as f:
                lanes_data = json.load(f)
            
            waypoints = []
            # Prioritize major roads (primary, secondary, tertiary) over residential/service
            priority_types = ['motorway', 'trunk', 'primary', 'secondary', 'tertiary']
            other_types = ['unclassified', 'residential', 'service']
            
            # First, collect waypoints from priority road types
            for lane_id, lane_info in lanes_data.get('lanes', {}).items():
                highway_type = lane_info.get('highway_type', '').lower()
                if highway_type in priority_types:
                    for wp in lane_info.get('waypoints', []):
                        waypoints.append((
                            float(wp.get('x', 0.0)),
                            float(wp.get('y', 0.0)),
                            float(wp.get('yaw', 0.0))
                        ))
            
            # If we don't have enough, add from other road types
            if len(waypoints) < 10:
                for lane_id, lane_info in lanes_data.get('lanes', {}).items():
                    highway_type = lane_info.get('highway_type', '').lower()
                    if highway_type in other_types:
                        for wp in lane_info.get('waypoints', []):
                            waypoints.append((
                                float(wp.get('x', 0.0)),
                                float(wp.get('y', 0.0)),
                                float(wp.get('yaw', 0.0))
                            ))
            
            if waypoints:
                return waypoints
    
    # Fallback to regular waypoints file
    with open(waypoints_file, 'r') as f:
        data = json.load(f)
    
    waypoints = []
    for wp in data.get('waypoints', []):
        waypoints.append((
            float(wp.get('x', 0.0)),
            float(wp.get('y', 0.0)),
            float(wp.get('yaw', 0.0))
        ))
    
    return waypoints


def select_street_spawn_points(
    waypoints: List[Tuple[float, float, float]],
    num_points: int = 3,
    min_distance: float = 5.0
) -> List[Tuple[float, float, float]]:
    """
    Select spawn points on streets with minimum distance between them.
    Prefers waypoints that are not at origin (0,0) to avoid building interiors.
    
    Args:
        waypoints: List of (x, y, yaw) waypoints
        num_points: Number of spawn points to select
        min_distance: Minimum distance between spawn points (meters)
    
    Returns:
        List of selected spawn points (x, y, yaw)
    """
    if not waypoints:
        return []
    
    # Filter out waypoints at origin (likely not real streets)
    filtered_waypoints = [
        wp for wp in waypoints
        if abs(wp[0]) > 1.0 or abs(wp[1]) > 1.0  # Not at origin
    ]
    
    # If filtering removed all waypoints, use original list
    if not filtered_waypoints:
        filtered_waypoints = waypoints
    
    if len(filtered_waypoints) <= num_points:
        return filtered_waypoints[:num_points]
    
    selected = []
    available = filtered_waypoints.copy()
    random.shuffle(available)  # Randomize selection
    
    for wp in available:
        if len(selected) >= num_points:
            break
        
        x, y, yaw = wp
        
        # Check minimum distance from already selected points
        too_close = False
        for sx, sy, _ in selected:
            dist = ((x - sx)**2 + (y - sy)**2)**0.5
            if dist < min_distance:
                too_close = True
                break
        
        if not too_close:
            selected.append(wp)
    
    # If we didn't get enough points, fill with remaining waypoints (relax distance requirement)
    while len(selected) < num_points and len(available) > len(selected):
        for wp in available:
            if wp not in selected:
                selected.append(wp)
                break
        if len(selected) >= num_points:
            break
    
    return selected[:num_points]


def main():
    if len(sys.argv) < 2:
        print("Usage: get_street_spawn_points.py <waypoints.json> [num_points] [min_distance]")
        print("  waypoints.json: Path to waypoints JSON file")
        print("  num_points: Number of spawn points (default: 3)")
        print("  min_distance: Minimum distance between points in meters (default: 5.0)")
        sys.exit(1)
    
    waypoints_file = sys.argv[1]
    num_points = int(sys.argv[2]) if len(sys.argv) > 2 else 3
    min_distance = float(sys.argv[3]) if len(sys.argv) > 3 else 5.0
    
    if not Path(waypoints_file).exists():
        print(f"Error: Waypoints file not found: {waypoints_file}")
        sys.exit(1)
    
    waypoints = load_waypoints(waypoints_file, prefer_lanes=True)
    print(f"📖 Loaded {len(waypoints)} street waypoints from {waypoints_file}")
    
    if not waypoints:
        print("⚠️  No waypoints found! Camera will use default position (0, 0, 5.0)")
        print("   This might place camera inside a building. Check waypoints file.")
    
    spawn_points = select_street_spawn_points(waypoints, num_points, min_distance)
    print(f"📍 Selected {len(spawn_points)} street spawn points")
    
    # Output as JSON for easy parsing
    output = {
        'spawn_points': [
            {'x': x, 'y': y, 'yaw': yaw}
            for x, y, yaw in spawn_points
        ],
        'camera_position': {
            'x': spawn_points[0][0] if spawn_points else 0.0,
            'y': spawn_points[0][1] if spawn_points else 0.0,
            'z': 15.0,  # Height above ground (higher to see over buildings)
            'pitch': -0.7,  # Look down more to see streets
            'yaw': spawn_points[0][2] if spawn_points else 0.0
        }
    }
    
    print(json.dumps(output, indent=2))
    
    # Also print human-readable format
    print("\n📍 Spawn Points:")
    for i, (x, y, yaw) in enumerate(spawn_points, 1):
        print(f"  Robot {i}: x={x:.2f}, y={y:.2f}, yaw={yaw:.2f}")
    
    if spawn_points:
        cam = output['camera_position']
        print(f"\n📷 Camera Position:")
        print(f"  x={cam['x']:.2f}, y={cam['y']:.2f}, z={cam['z']:.2f}")
        print(f"  pitch={cam['pitch']:.2f}, yaw={cam['yaw']:.2f}")


if __name__ == '__main__':
    main()


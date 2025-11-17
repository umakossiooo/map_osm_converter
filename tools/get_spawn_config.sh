#!/usr/bin/env bash
# Get spawn configuration from waypoints file for ROS 2 launch files
# Usage: get_spawn_config.sh <waypoints.json> <num_robots>

WAYPOINTS_FILE="$1"
NUM_ROBOTS="${2:-3}"

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

if [ ! -f "$WAYPOINTS_FILE" ]; then
    echo "Error: Waypoints file not found: $WAYPOINTS_FILE" >&2
    exit 1
fi

# Get spawn points
SPAWN_DATA=$(python3 "$SCRIPT_DIR/get_street_spawn_points.py" "$WAYPOINTS_FILE" "$NUM_ROBOTS" 5.0 2>/dev/null)

if [ -z "$SPAWN_DATA" ]; then
    echo "Error: Could not extract spawn points" >&2
    exit 1
fi

# Output as environment variables for launch files
echo "$SPAWN_DATA" | python3 -c "
import sys, json
data = json.load(sys.stdin)
spawn_points = data['spawn_points']
camera = data['camera_position']

# Output spawn points
for i, sp in enumerate(spawn_points):
    print(f'export SPAWN_{i}_X={sp[\"x\"]}')
    print(f'export SPAWN_{i}_Y={sp[\"y\"]}')
    print(f'export SPAWN_{i}_YAW={sp[\"yaw\"]}')

# Output camera position
print(f'export CAMERA_X={camera[\"x\"]}')
print(f'export CAMERA_Y={camera[\"y\"]}')
print(f'export CAMERA_Z={camera[\"z\"]}')
print(f'export CAMERA_PITCH={camera[\"pitch\"]}')
print(f'export CAMERA_YAW={camera[\"yaw\"]}')

# Output as JSON for Python launch files
print('---JSON---')
print(json.dumps(data, indent=2))
"


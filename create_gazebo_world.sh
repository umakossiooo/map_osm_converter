#!/usr/bin/env bash
set -euo pipefail

MODEL_NAME=${1:-city_3d}
WORLD_NAME=${2:-$MODEL_NAME}
WORLD_DIR=${3:-worlds}
WAYPOINTS_FILE=${4:-}  # Optional waypoints file path
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

mkdir -p "$WORLD_DIR"

# Always create .sdf file (ROS 2 / Gazebo Sim Harmonic standard)
WORLD_FILE_PATH="$WORLD_DIR/$WORLD_NAME.sdf"

# Try to get spawn points from waypoints file (if available)
# Default: Higher camera position to see over buildings even if waypoint extraction fails
CAMERA_X=0.0
CAMERA_Y=0.0
CAMERA_Z=20.0  # Higher default to see over buildings
CAMERA_PITCH=-0.8  # Look down more to see streets
CAMERA_YAW=0.0

# Use provided waypoints file, or try to find it in the default location
if [ -z "$WAYPOINTS_FILE" ] || [ ! -f "$WAYPOINTS_FILE" ]; then
    WAYPOINTS_FILE="$SCRIPT_DIR/../outputs/$MODEL_NAME/${MODEL_NAME}_waypoints.json"
fi
if [ -f "$WAYPOINTS_FILE" ] && [ -f "$SCRIPT_DIR/tools/get_street_spawn_points.py" ]; then
    echo "📍 Extracting street spawn points for camera positioning..."
    SPAWN_DATA=$(python3 "$SCRIPT_DIR/tools/get_street_spawn_points.py" "$WAYPOINTS_FILE" 1 0.0 2>&1)
    
    # Check if we got valid data (not an error message)
    if echo "$SPAWN_DATA" | grep -q '"camera_position"'; then
        CAMERA_X=$(echo "$SPAWN_DATA" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['camera_position']['x'])" 2>/dev/null || echo "")
        CAMERA_Y=$(echo "$SPAWN_DATA" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['camera_position']['y'])" 2>/dev/null || echo "")
        CAMERA_Z=$(echo "$SPAWN_DATA" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['camera_position']['z'])" 2>/dev/null || echo "")
        CAMERA_PITCH=$(echo "$SPAWN_DATA" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['camera_position']['pitch'])" 2>/dev/null || echo "")
        CAMERA_YAW=$(echo "$SPAWN_DATA" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['camera_position']['yaw'])" 2>/dev/null || echo "")
        
        # Validate coordinates (not at origin and reasonable values)
        if [ -n "$CAMERA_X" ] && [ -n "$CAMERA_Y" ] && \
           [ "$CAMERA_X" != "0.0" ] && [ "$CAMERA_Y" != "0.0" ] && \
           [ "$(echo "$CAMERA_X" | awk '{if ($1 < -10000 || $1 > 10000) print "bad"; else print "ok"}')" = "ok" ]; then
            echo "   ✅ Camera positioned on street at ($CAMERA_X, $CAMERA_Y)"
        else
            echo "   ⚠️  Invalid coordinates, using high default camera position"
            CAMERA_X="0.0"
            CAMERA_Y="0.0"
            CAMERA_Z="20.0"  # High enough to see over buildings
            CAMERA_PITCH="-0.8"  # Look down to see streets
            CAMERA_YAW="0.0"
        fi
    else
        echo "   ⚠️  Could not extract street waypoints, trying to find any valid waypoint..."
        # Try to find any non-zero waypoint as fallback
        if [ -f "$WAYPOINTS_FILE" ]; then
            FALLBACK_WP=$(python3 -c "
import json
try:
    with open('$WAYPOINTS_FILE', 'r') as f:
        data = json.load(f)
    for wp in data.get('waypoints', [])[:100]:  # Check first 100 waypoints
        x, y = float(wp.get('x', 0)), float(wp.get('y', 0))
        if abs(x) > 10 or abs(y) > 10:  # Not near origin
            print(f'{x},{y}')
            break
except:
    pass
" 2>/dev/null)
            if [ -n "$FALLBACK_WP" ]; then
                CAMERA_X=$(echo "$FALLBACK_WP" | cut -d',' -f1)
                CAMERA_Y=$(echo "$FALLBACK_WP" | cut -d',' -f2)
                CAMERA_Z="20.0"
                CAMERA_PITCH="-0.8"
                echo "   ✅ Using fallback waypoint at ($CAMERA_X, $CAMERA_Y)"
            else
                echo "   ⚠️  No valid waypoints found, using high default position"
            fi
        else
            echo "   ⚠️  Waypoints file not found, using high default camera position"
        fi
    fi
else
    echo "   ⚠️  Waypoints file not found, using high default camera position"
fi

cat <<EOF > "$WORLD_FILE_PATH"
<?xml version="1.0"?>
<sdf version="1.8">
  <world name="${WORLD_NAME}">
    <gravity>0 0 -9.81</gravity>
    <plugin
      filename="gz-sim-physics-system"
      name="gz::sim::systems::Physics">
    </plugin>
    <plugin
      filename="gz-sim-sensors-system"
      name="gz::sim::systems::Sensors">
      <render_engine>vulkan</render_engine>
    </plugin>
    <plugin
      filename="gz-sim-scene-broadcaster-system"
      name="gz::sim::systems::SceneBroadcaster">
    </plugin>
    <plugin
      filename="gz-sim-user-commands-system"
      name="gz::sim::systems::UserCommands">
    </plugin>
    <plugin filename="gz-sim-imu-system"
        name="gz::sim::systems::Imu">
    </plugin>

    <!-- City model generated via map_osm_converter -->
    <include>
      <name>$MODEL_NAME</name>
EOF

# Add pose transformation for bari_3d model (matches existing bari_world.sdf structure)
# This converts OSM mesh (Y-up) into Gazebo's Z-up frame and positions it correctly
if [ "$MODEL_NAME" = "bari_3d" ]; then
    cat <<EOF >> "$WORLD_FILE_PATH"
      <!-- Convert the OSM mesh (Y-up) into Gazebo's Z-up frame, rotate 90° around Z, and shift so the origin sits on an open street. -->
      <pose>-66 -275 0 1.5708 0 1.5708</pose>
EOF
else
    cat <<EOF >> "$WORLD_FILE_PATH"
      <pose>0 0 0 1.5708 0 0</pose>
EOF
fi

cat <<EOF >> "$WORLD_FILE_PATH"
      <uri>model://$MODEL_NAME</uri>
    </include>

    <!-- Camera defaults to follow the spawned Ackermann chassis -->
    <gui fullscreen="0">
      <camera name="follow_camera">
        <pose>-8 0 4 0.4 0.6 0</pose>
        <view_controller>orbit</view_controller>
        <track_visual>saye::base_link::BaseVisual</track_visual>
      </camera>
      <!-- Additional street camera for initial view (if waypoints available) -->
EOF

# Add street camera only if we have valid waypoint coordinates
if [ "$CAMERA_X" != "0.0" ] || [ "$CAMERA_Y" != "0.0" ]; then
    cat <<EOF >> "$WORLD_FILE_PATH"
      <camera name="street_camera">
        <pose>$CAMERA_X $CAMERA_Y $CAMERA_Z 0 $CAMERA_PITCH $CAMERA_YAW</pose>
        <view_controller>orbit</view_controller>
      </camera>
EOF
fi

cat <<EOF >> "$WORLD_FILE_PATH"
    </gui>

  </world>
</sdf>
EOF

echo "🌍 World '$WORLD_NAME' created:"
echo "   - $WORLD_FILE_PATH (ROS 2 compatible, ready for ackermann project)"
echo "   - Camera configured to follow robot (saye::base_link::BaseVisual)"
if [ "$CAMERA_X" != "0.0" ] || [ "$CAMERA_Y" != "0.0" ]; then
    echo "   - Additional street camera at ($CAMERA_X, $CAMERA_Y, $CAMERA_Z)"
fi

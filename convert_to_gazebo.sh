#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

INPUT_OSM=${1:-data/city.osm}
MODEL_NAME=${2:-city_3d}
WORLD_NAME=${3:-$MODEL_NAME}

OUTPUT_DIR=outputs/$MODEL_NAME
MODEL_DIR=models/$MODEL_NAME
WORLD_DIR=worlds

# Resolve OSM file path (handle both relative and absolute paths)
if [[ "$INPUT_OSM" = /* ]]; then
    OSM_PATH="$INPUT_OSM"
else
    OSM_PATH="$SCRIPT_DIR/$INPUT_OSM"
fi

# === 0. Ensure Docker service is running ===
echo "🛠 Ensuring Docker service 'osm2world' is running..."
docker compose up -d osm2world >/dev/null

if ! docker compose exec osm2world bash -c "[ -f /opt/osm2world/OSM2World.jar ]"; then
  cat <<'EOF'
❌ /opt/osm2world/OSM2World.jar not found inside the container.
   Make sure you extracted OSM2World-0.4.0 into ./osm2world/ on the host,
   then run:
     docker compose down
     docker compose up -d
EOF
  exit 1
fi

# === 1. Create output directory ===
mkdir -p "$OUTPUT_DIR"

# === 2. Pre-filter OSM to exclude narrow roads ===
FILTERED_OSM="$OUTPUT_DIR/${MODEL_NAME}_navigable.osm"
OSM_FOR_CONVERSION="$OSM_PATH"

if [ -f "$SCRIPT_DIR/tools/filter_osm_for_navigation.py" ] && [ -f "$OSM_PATH" ]; then
    echo "🔍 Pre-filtering OSM to exclude narrow roads..."
    if python3 "$SCRIPT_DIR/tools/filter_osm_for_navigation.py" "$OSM_PATH" "$FILTERED_OSM" 2.5 && [ -f "$FILTERED_OSM" ]; then
        OSM_FOR_CONVERSION="$FILTERED_OSM"
        echo "   ✅ Using filtered OSM (narrow roads excluded)"
    else
        echo "   ⚠️  Filtering failed, using original OSM"
    fi
fi

# === 3. Convert OSM to OBJ with OSM2World ===
echo "🚀 Converting to OBJ..."
ENHANCED_CONFIG="$SCRIPT_DIR/config/enhanced.properties"
CONFIG_ARG=""
if [ -f "$ENHANCED_CONFIG" ]; then
    CONFIG_ARG="--config /workspace/config/enhanced.properties"
    echo "   Using enhanced configuration"
else
    CONFIG_ARG="--config /opt/osm2world/standard.properties"
    echo "   Using standard configuration"
fi

docker compose exec osm2world bash -c \
"java -Xms512m -Xmx4g -jar /opt/osm2world/OSM2World.jar \
  -i $OSM_FOR_CONVERSION \
  -o $OUTPUT_DIR/$MODEL_NAME.obj \
  $CONFIG_ARG"

if ! docker compose exec osm2world bash -c "[ -f /workspace/$OUTPUT_DIR/$MODEL_NAME.obj ]"; then
  echo "❌ OSM2World conversion failed. Check logs above."
  exit 1
fi

# === 4. Compute vertex normals ===
echo "🧮 Computing vertex normals..."
docker compose exec osm2world bash -c \
"python3 /workspace/tools/add_obj_normals.py \
  /workspace/$OUTPUT_DIR/$MODEL_NAME.obj \
  /workspace/$OUTPUT_DIR/${MODEL_NAME}_with_normals.obj && \
mv /workspace/$OUTPUT_DIR/${MODEL_NAME}_with_normals.obj /workspace/$OUTPUT_DIR/$MODEL_NAME.obj"

# === 5. Package a Gazebo model ===
echo "📦 Creating folder $MODEL_DIR..."
mkdir -p "$MODEL_DIR/meshes"

cp "$OUTPUT_DIR/$MODEL_NAME.obj" "$MODEL_DIR/meshes/"
cp "$OUTPUT_DIR/$MODEL_NAME.obj.mtl" "$MODEL_DIR/meshes/" 2>/dev/null || true

# Unify road colors: navigable roads (dark grey) vs non-navigable paths (lighter grey)
if [ -f "$MODEL_DIR/meshes/$MODEL_NAME.obj.mtl" ] && [ -f "$SCRIPT_DIR/tools/unify_road_colors.py" ]; then
    echo "🎨 Color-coding roads for navigation clarity..."
    echo "   - Navigable roads (Ackermann vehicles): Dark grey (0.15, 0.15, 0.15)"
    echo "   - Non-navigable paths (too narrow): Light grey (0.4, 0.4, 0.4)"
    python3 "$SCRIPT_DIR/tools/unify_road_colors.py" "$MODEL_DIR/meshes/$MODEL_NAME.obj.mtl" 0.15 0.15 0.15 0.4 0.4 0.4
    echo "   ✅ Roads color-coded: Dark = navigable, Light = non-navigable"
fi

# Copy textures and assets
[ -d "$OUTPUT_DIR/textures" ] && cp -r "$OUTPUT_DIR/textures" "$MODEL_DIR/meshes/"

echo "🎨 Copying OSM2World assets..."
docker compose exec osm2world bash -c \
"[ -d /opt/osm2world/textures ] && {
  cp -r /opt/osm2world/textures/cc0textures /workspace/$MODEL_DIR/meshes/ 2>/dev/null
  cp -r /opt/osm2world/textures/custom /workspace/$MODEL_DIR/meshes/ 2>/dev/null
  find /opt/osm2world/textures -maxdepth 1 -type f \( -name '*.jpg' -o -name '*.png' -o -name '*.JPG' -o -name '*.PNG' \) -exec cp {} /workspace/$MODEL_DIR/meshes/ \; 2>/dev/null
  [ -d /opt/osm2world/models ] && cp -r /opt/osm2world/models /workspace/$MODEL_DIR/meshes/ 2>/dev/null
  [ -d /opt/osm2world/resources ] && cp -r /opt/osm2world/resources /workspace/$MODEL_DIR/meshes/ 2>/dev/null
  echo '✅ Assets copied'
}" || true

cat <<EOF > "$MODEL_DIR/model.config"
<?xml version="1.0"?>
<model>
  <name>$MODEL_NAME</name>
  <version>1.0</version>
  <sdf version="1.9">model.sdf</sdf>
</model>
EOF

cat <<EOF > "$MODEL_DIR/model.sdf"
<?xml version="1.0" ?>
<sdf version="1.9">
  <!-- OSM-derived city model with roads/lanes tagged for DRL coordinate extraction -->
  <!-- Note: For accurate waypoint extraction, use tools/extract_osm_waypoints.py on the source OSM file -->
  <!-- Textures and materials from OSM2World are preserved - streets, buildings, etc. will have colors -->
  <model name="$MODEL_NAME">
    <static>true</static>
    <pose>0 0 0 1.5708 0 0</pose>
    <link name="${MODEL_NAME}_link">
      <!-- Road/lane visual: Uses OBJ materials/textures from OSM2World for realistic colors -->
      <!-- Visual name contains "road" and "lane" keywords for fleet_drl coordinate extractor -->
      <visual name="road_lane_street_visual">
        <geometry>
          <mesh>
            <uri>model://$MODEL_NAME/meshes/$MODEL_NAME.obj</uri>
          </mesh>
        </geometry>
        <!-- Material not specified - uses OBJ's MTL file materials for realistic textures -->
      </visual>
      <collision name="collision">
        <geometry>
          <mesh>
            <uri>model://$MODEL_NAME/meshes/$MODEL_NAME.obj</uri>
          </mesh>
        </geometry>
      </collision>
    </link>
  </model>
</sdf>
EOF

echo "✅ Model '$MODEL_NAME' created in $MODEL_DIR/"
echo "To use it, export:"
echo "  export GZ_SIM_RESOURCE_PATH=\$GZ_SIM_RESOURCE_PATH:$(pwd)/models"
echo "Then include it in Gazebo with:"
echo "  <include><uri>model://$MODEL_NAME</uri></include>"

# === 6. Extract waypoints from OSM ===
echo "📍 Extracting waypoints from OSM..."
WAYPOINTS_OUT="$SCRIPT_DIR/$OUTPUT_DIR/${MODEL_NAME}_waypoints.json"

if [ -f "$SCRIPT_DIR/tools/extract_osm_waypoints.py" ] && [ -f "$OSM_PATH" ]; then
    if python3 "$SCRIPT_DIR/tools/extract_osm_waypoints.py" "$OSM_PATH" -o "$WAYPOINTS_OUT" -n 999999 -s 2.0 -m 5.0; then
        NAV_LANES_OUT="$SCRIPT_DIR/$OUTPUT_DIR/${MODEL_NAME}_waypoints_navigable_lanes.json"
        [ -f "$NAV_LANES_OUT" ] && {
            LANE_COUNT=$(python3 -c "import json; d=json.load(open('$NAV_LANES_OUT')); print(len(d.get('lanes', {})))" 2>/dev/null || echo "unknown")
            WP_COUNT=$(python3 -c "import json; d=json.load(open('$NAV_LANES_OUT')); print(d.get('total_waypoints', 0))" 2>/dev/null || echo "unknown")
            echo "✅ Navigable lanes: $LANE_COUNT lanes, $WP_COUNT waypoints → $OUTPUT_DIR/${MODEL_NAME}_waypoints_navigable_lanes.json"
        }
    else
        echo "❌ Waypoint extraction failed!"
    fi
else
    echo "⚠️  Waypoint extraction skipped"
fi

# === 7. Create Gazebo world file ===
echo "🌍 Creating Gazebo world file..."
WORLD_FILE_NAME=$([ "$MODEL_NAME" = "bari_3d" ] && echo "bari_world" || echo "$WORLD_NAME")
WAYPOINTS_FILE="$SCRIPT_DIR/$OUTPUT_DIR/${MODEL_NAME}_waypoints.json"

if [ -f "$SCRIPT_DIR/create_gazebo_world.sh" ]; then
    bash "$SCRIPT_DIR/create_gazebo_world.sh" "$MODEL_NAME" "$WORLD_FILE_NAME" "$WORLD_DIR" \
        "$([ -f "$WAYPOINTS_FILE" ] && echo "$WAYPOINTS_FILE" || echo "")"
    echo "✅ World file: $WORLD_DIR/${WORLD_FILE_NAME}.sdf"
    
    # Copy to ackermann project if bari_3d
    [ "$MODEL_NAME" = "bari_3d" ] && [ -d "$SCRIPT_DIR/../ackermann-vehicle-gzsim-ros2/saye_description/worlds" ] && \
        cp "$WORLD_DIR/${WORLD_FILE_NAME}.sdf" "$SCRIPT_DIR/../ackermann-vehicle-gzsim-ros2/saye_description/worlds/${WORLD_FILE_NAME}.sdf" && \
        echo "✅ Copied to ackermann project"
fi

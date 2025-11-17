#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

INPUT_OSM=${1:-data/city.osm}
MODEL_NAME=${2:-city_3d}
WORLD_NAME=${3:-$MODEL_NAME}

OUTPUT_DIR=outputs/$MODEL_NAME
MODEL_DIR=models/$MODEL_NAME
WORLD_DIR=worlds

# === 0. Ensure the Docker service is running ===
echo "🛠 Ensuring Docker service 'osm2world' is running..."
docker compose up -d osm2world >/dev/null

# === 0b. Verify OSM2World binaries are available inside the container ===
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

# === 1. Create organized output directory ===
mkdir -p "$OUTPUT_DIR"

# === 2. Convert the OSM map into OBJ with OSM2World ===
echo "🚀 Converting $INPUT_OSM to OBJ with enhanced graphics..."
echo "   - Terrain generation: enabled"
echo "   - Building colors: enabled"
echo "   - Vegetation (trees): enabled"
echo "   - Textures: enabled for streets, buildings, green areas"
echo "   - Billboards: enabled for better visuals"

# Use enhanced config if available, otherwise fall back to standard
ENHANCED_CONFIG="$SCRIPT_DIR/config/enhanced.properties"
if [ -f "$ENHANCED_CONFIG" ]; then
    echo "   Using enhanced configuration..."
    docker compose exec osm2world bash -c \
    "java -Xms512m -Xmx4g -jar /opt/osm2world/OSM2World.jar \
      -i $INPUT_OSM \
      -o $OUTPUT_DIR/$MODEL_NAME.obj \
      --config /workspace/config/enhanced.properties"
else
    echo "   Using standard OSM2World configuration..."
    docker compose exec osm2world bash -c \
    "java -Xms512m -Xmx4g -jar /opt/osm2world/OSM2World.jar \
      -i $INPUT_OSM \
      -o $OUTPUT_DIR/$MODEL_NAME.obj \
      --config /opt/osm2world/standard.properties"
fi

if ! docker compose exec osm2world bash -c "[ -f /workspace/$OUTPUT_DIR/$MODEL_NAME.obj ]"; then
  echo "❌ OSM2World did not produce $OUTPUT_DIR/$MODEL_NAME.obj. Check the conversion log above for geometry warnings."
  exit 1
fi

# === 3. Recompute normals so DART/Bullet accept the mesh ===
echo "🧮 Computing vertex normals..."
docker compose exec osm2world bash -c \
"python3 /workspace/tools/add_obj_normals.py \
  /workspace/$OUTPUT_DIR/$MODEL_NAME.obj \
  /workspace/$OUTPUT_DIR/${MODEL_NAME}_with_normals.obj"
docker compose exec osm2world bash -c \
"mv /workspace/$OUTPUT_DIR/${MODEL_NAME}_with_normals.obj /workspace/$OUTPUT_DIR/$MODEL_NAME.obj"

# === 4. Package a Gazebo model ===
echo "📦 Creating folder $MODEL_DIR..."
mkdir -p "$MODEL_DIR/meshes"

cp "$OUTPUT_DIR/$MODEL_NAME.obj" "$MODEL_DIR/meshes/"
cp "$OUTPUT_DIR/$MODEL_NAME.obj.mtl" "$MODEL_DIR/meshes/" 2>/dev/null || true

# Copy textures from OSM2World output (if generated)
if [ -d "$OUTPUT_DIR/textures" ]; then
  echo "📸 Copying textures from OSM2World output..."
  cp -r "$OUTPUT_DIR/textures" "$MODEL_DIR/meshes/"
fi

# Copy OSM2World texture library and models to model directory for Gazebo
# This ensures streets, buildings, green areas, etc. have realistic colors and props
echo "🎨 Copying OSM2World assets for beautiful graphics..."
docker compose exec osm2world bash -c \
"if [ -d /opt/osm2world/textures ]; then
  # Copy texture libraries
  cp -r /opt/osm2world/textures/cc0textures /workspace/$MODEL_DIR/meshes/ 2>/dev/null || true
  cp -r /opt/osm2world/textures/custom /workspace/$MODEL_DIR/meshes/ 2>/dev/null || true
  find /opt/osm2world/textures -maxdepth 1 -type f \( -name '*.jpg' -o -name '*.png' -o -name '*.JPG' -o -name '*.PNG' -o -name '*.svg' \) -exec cp {} /workspace/$MODEL_DIR/meshes/ \; 2>/dev/null || true
  echo '✅ Textures copied (streets, buildings, grass, etc.)'
  
  # Copy models/props if available (cars, trees, etc.)
  if [ -d /opt/osm2world/models ]; then
    cp -r /opt/osm2world/models /workspace/$MODEL_DIR/meshes/ 2>/dev/null || true
    echo '✅ Models/props copied'
  fi
  
  # Copy resources (shaders, etc.)
  if [ -d /opt/osm2world/resources ]; then
    cp -r /opt/osm2world/resources /workspace/$MODEL_DIR/meshes/ 2>/dev/null || true
  fi
else
  echo '⚠️  OSM2World textures directory not found'
fi" || echo "⚠️  Could not copy OSM2World assets (may still work if textures are embedded)"

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

# === 5. Generate a convenience world file ===
echo "🌍 Generating Gazebo world file..."
mkdir -p "$WORLD_DIR"
bash "$SCRIPT_DIR/create_gazebo_world.sh" "$MODEL_NAME" "$WORLD_NAME" "$WORLD_DIR"

# === 6. Extract waypoints from OSM for DRL coordinate extraction ===
echo "📍 Extracting road waypoints from OSM for fleet_drl..."
# Resolve OSM file path (handle both relative and absolute paths)
if [[ "$INPUT_OSM" = /* ]]; then
    OSM_PATH="$INPUT_OSM"
else
    OSM_PATH="$SCRIPT_DIR/$INPUT_OSM"
fi

if [ -f "$SCRIPT_DIR/tools/extract_osm_waypoints.py" ] && [ -f "$OSM_PATH" ]; then
    python3 "$SCRIPT_DIR/tools/extract_osm_waypoints.py" \
        "$OSM_PATH" \
        -o "$SCRIPT_DIR/$OUTPUT_DIR/${MODEL_NAME}_waypoints.json" \
        -n 999999 \
        -s 2.0 \
        -m 5.0
    if [ -f "$SCRIPT_DIR/$OUTPUT_DIR/${MODEL_NAME}_waypoints.json" ]; then
        echo "✅ Waypoints extracted to $OUTPUT_DIR/${MODEL_NAME}_waypoints.json"
        echo "   - Contains ALL map coordinates (no sampling)"
        if [ -f "$SCRIPT_DIR/$OUTPUT_DIR/${MODEL_NAME}_waypoints_lanes.json" ]; then
            echo "✅ Lanes/streets organized in $OUTPUT_DIR/${MODEL_NAME}_waypoints_lanes.json"
            echo "   - Use this file to pick delivery coordinates from specific lanes"
        fi
        echo "   All outputs organized in: $OUTPUT_DIR/"
    else
        echo "⚠️  Waypoint extraction completed but output file not found"
    fi
else
    if [ ! -f "$SCRIPT_DIR/tools/extract_osm_waypoints.py" ]; then
        echo "⚠️  Waypoint extractor not found at $SCRIPT_DIR/tools/extract_osm_waypoints.py"
    fi
    if [ ! -f "$OSM_PATH" ]; then
        echo "⚠️  OSM file not found: $OSM_PATH"
    fi
    echo "   Run manually: python3 tools/extract_osm_waypoints.py $OSM_PATH -o $OUTPUT_DIR/${MODEL_NAME}_waypoints.json"
fi

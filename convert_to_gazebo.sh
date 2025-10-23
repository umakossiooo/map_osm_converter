#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

INPUT_OSM=${1:-data/city.osm}
MODEL_NAME=${2:-city_3d}
WORLD_NAME=${3:-$MODEL_NAME}

OUTPUT_DIR=outputs
MODEL_DIR=models/$MODEL_NAME
WORLD_DIR=worlds

# === 0. Ensure the Docker service is running ===
echo "🛠 Ensuring Docker service 'osm2world' is running..."
docker compose up -d osm2world >/dev/null

# === 1. Convert the OSM map into OBJ with OSM2World ===
echo "🚀 Converting $INPUT_OSM to OBJ..."
docker compose exec osm2world bash -c \
"java -Xms512m -Xmx4g -jar /opt/osm2world/OSM2World.jar \
  -i $INPUT_OSM \
  -o $OUTPUT_DIR/$MODEL_NAME.obj"

if ! docker compose exec osm2world bash -c "[ -f /workspace/$OUTPUT_DIR/$MODEL_NAME.obj ]"; then
  echo "❌ OSM2World did not produce $OUTPUT_DIR/$MODEL_NAME.obj. Check the conversion log above for geometry warnings."
  exit 1
fi

# === 1b. Recompute normals so DART/Bullet accept the mesh ===
echo "🧮 Computing vertex normals..."
docker compose exec osm2world bash -c \
"python3 /workspace/tools/add_obj_normals.py \
  /workspace/$OUTPUT_DIR/$MODEL_NAME.obj \
  /workspace/$OUTPUT_DIR/${MODEL_NAME}_with_normals.obj"
docker compose exec osm2world bash -c \
"mv /workspace/$OUTPUT_DIR/${MODEL_NAME}_with_normals.obj /workspace/$OUTPUT_DIR/$MODEL_NAME.obj"

# === 2. Package a Gazebo model ===
echo "📦 Creating folder $MODEL_DIR..."
mkdir -p "$MODEL_DIR/meshes"

cp "$OUTPUT_DIR/$MODEL_NAME.obj" "$MODEL_DIR/meshes/"
cp "$OUTPUT_DIR/$MODEL_NAME.obj.mtl" "$MODEL_DIR/meshes/" 2>/dev/null || true
if [ -d "$OUTPUT_DIR/textures" ]; then
  cp -r "$OUTPUT_DIR/textures" "$MODEL_DIR/meshes/"
fi

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
  <model name="$MODEL_NAME">
    <static>true</static>
    <pose>0 0 0 1.5708 0 0</pose>
    <link name="${MODEL_NAME}_link">
      <visual name="visual">
        <geometry>
          <mesh>
            <uri>model://$MODEL_NAME/meshes/$MODEL_NAME.obj</uri>
          </mesh>
        </geometry>
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

# === 3. Generate a convenience world file ===
echo "🌍 Generating Gazebo world file..."
mkdir -p "$WORLD_DIR"
bash "$SCRIPT_DIR/create_gazebo_world.sh" "$MODEL_NAME" "$WORLD_NAME" "$WORLD_DIR"

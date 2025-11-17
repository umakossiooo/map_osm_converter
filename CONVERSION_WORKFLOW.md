# OSM to Gazebo Conversion Workflow - Complete Guide

This guide provides exact step-by-step commands to convert OSM maps to Gazebo models with lane tagging and visualize them inside the container. Uses `bari.osm` as an example.

## Prerequisites

1. **Ensure OSM2World binaries are extracted**:
   ```bash
   cd /home/studente/ackermann_sim/src/map_osm_converter
   ls -la osm2world/OSM2World.jar  # Should exist
   ```

2. **Build and start Docker container**:
   ```bash
   cd /home/studente/ackermann_sim/src/map_osm_converter
   docker compose build
   docker compose up -d
   ```

3. **Verify container is running**:
   ```bash
   docker compose ps
   ```

## Step-by-Step Conversion Workflow (bari.osm example)

### Step 1: Clean Previous Conversions (Optional)

If you've converted before and want a fresh start:
```bash
cd /home/studente/ackermann_sim/src/map_osm_converter
rm -rf models/bari_3d outputs/bari_3d.* worlds/bari_world.world
```

### Step 2: Convert bari.osm to Gazebo Model

Run the conversion script:
```bash
cd /home/studente/ackermann_sim/src/map_osm_converter
./convert_to_gazebo.sh data/bari.osm bari_3d bari_world
```

**Expected output:**
- ✅ OSM2World conversion (may show warnings - these are normal)
- ✅ Vertex normals computed
- ✅ Model created in `models/bari_3d/`
- ✅ World file created at `worlds/bari_world.world`
- ✅ Waypoints extracted to `outputs/bari_3d_waypoints.json`
- ✅ Lanes organized in `outputs/bari_3d_waypoints_lanes.json`

### Step 3: Verify Conversion Outputs

Check that all files were generated:
```bash
cd /home/studente/ackermann_sim/src/map_osm_converter

# Check model directory
ls -la models/bari_3d/
# Should show: model.config, model.sdf, meshes/bari_3d.obj

# Check world file
ls -la worlds/bari_world.world

# Check waypoint files
ls -la outputs/bari_3d_waypoints.json
ls -la outputs/bari_3d_waypoints_lanes.json

# Verify waypoint count
python3 -c "import json; data=json.load(open('outputs/bari_3d_waypoints.json')); print(f\"Total waypoints: {data['num_waypoints']}\")"
```

### Step 4: Visualize the Map Inside Container

#### 4.1: Allow Docker to Access X11 Display (on host)

```bash
# On host machine
xhost +local:docker
export DISPLAY=:0  # Or your display number
```

#### 4.2: Launch Gazebo Inside Container (GUI Mode)

```bash
cd /home/studente/ackermann_sim/src/map_osm_converter

# Launch Gazebo with the world file
docker compose exec \
  -u root \
  -e DISPLAY=$DISPLAY \
  -e XDG_RUNTIME_DIR=/tmp/osm2world_x11 \
  osm2world \
  bash -lc 'mkdir -p ~/.gz && gz sim /workspace/worlds/bari_world.world'
```

**Alternative: Load just the model** (without world file):
```bash
docker compose exec \
  -u root \
  -e DISPLAY=$DISPLAY \
  -e XDG_RUNTIME_DIR=/tmp/osm2world_x11 \
  osm2world \
  bash -lc 'mkdir -p ~/.gz && gz sim /workspace/models/bari_3d/model.sdf'
```

#### 4.3: Launch Gazebo in Headless Mode (No GUI)

If you don't need visualization:
```bash
docker compose exec \
  -u root \
  osm2world \
  bash -lc 'mkdir -p ~/.gz && gz sim /workspace/worlds/bari_world.world -r -s'
```

**Note:** `-r` starts paused, `-s` runs headless. Remove `-r` to auto-start simulation.

### Step 5: Verify Model Resource Path

Ensure Gazebo can find the model. Inside the container:
```bash
docker compose exec osm2world bash

# Inside container, check resource path
echo $GZ_SIM_RESOURCE_PATH
# Should include: /workspace/models

# Test model discovery
gz model --list | grep bari_3d
```

### Step 6: Inspect Waypoints (Optional)

View available lanes/streets:
```bash
cd /home/studente/ackermann_sim/src/map_osm_converter

# List all lanes/streets
python3 -c "import json; data=json.load(open('outputs/bari_3d_waypoints_lanes.json')); print('Available lanes/streets:'); [print(f\"  - {name} ({info['num_waypoints']} waypoints)\") for name, info in data['lanes'].items()]"

# Get coordinates for a specific lane (replace 'lane_name' with actual name)
python3 -c "import json; data=json.load(open('outputs/bari_3d_waypoints_lanes.json')); lane_name=list(data['lanes'].keys())[0]; lane=data['lanes'][lane_name]; print(f\"Lane: {lane_name}\"); print(f\"Type: {lane['highway_type']}\"); print(f\"Waypoints: {lane['num_waypoints']}\"); print(f\"First 3 coordinates:\"); [print(f\"  ({wp['x']:.2f}, {wp['y']:.2f}, {wp['yaw']:.2f})\") for wp in lane['waypoints'][:3]]"
```

### Step 7: Copy Waypoints for DRL Training

```bash
cd /home/studente/ackermann_sim/src/map_osm_converter

# Copy waypoints to fleet_drl workspace
cp outputs/bari_3d_waypoints.json /home/studente/ackermann_sim/src/ackermann-vehicle-gzsim-ros2/waypoints.json

# Verify copy
ls -la /home/studente/ackermann_sim/src/ackermann-vehicle-gzsim-ros2/waypoints.json
```

## Complete Example: Full Workflow from Start

Here's the complete workflow assuming a fresh start:

```bash
# 1. Navigate to converter directory
cd /home/studente/ackermann_sim/src/map_osm_converter

# 2. Ensure Docker is running
docker compose up -d

# 3. Clean old conversions (if any)
rm -rf models/bari_3d outputs/bari_3d.* worlds/bari_world.world

# 4. Convert bari.osm
./convert_to_gazebo.sh data/bari.osm bari_3d bari_world

# 5. Verify outputs
ls -la models/bari_3d/
ls -la outputs/bari_3d_waypoints.json
ls -la outputs/bari_3d_waypoints_lanes.json

# 6. Set up X11 for visualization (on host)
xhost +local:docker
export DISPLAY=:0

# 7. Launch Gazebo inside container
docker compose exec \
  -u root \
  -e DISPLAY=$DISPLAY \
  -e XDG_RUNTIME_DIR=/tmp/osm2world_x11 \
  osm2world \
  bash -lc 'mkdir -p ~/.gz && gz sim /workspace/worlds/bari_world.world'

# 8. (In another terminal) Copy waypoints for DRL
cp outputs/bari_3d_waypoints.json /home/studente/ackermann_sim/src/ackermann-vehicle-gzsim-ros2/waypoints.json
```

## Output Files Explained

After conversion, you'll have:

1. **`models/bari_3d/`** - Gazebo model directory:
   - `model.config` - Model metadata
   - `model.sdf` - Model definition with lane tagging
   - `meshes/bari_3d.obj` - 3D mesh file

2. **`worlds/bari_world.world`** - Gazebo world file:
   - References `model://bari_3d`
   - Ready to launch in Gazebo

3. **`outputs/bari_3d_waypoints.json`** - All map coordinates:
   - `waypoints`: All delivery candidate locations (x, y, yaw)
   - `lane_network`: Full lane network (same as waypoints)
   - `metadata`: Extraction parameters

4. **`outputs/bari_3d_waypoints_lanes.json`** - Lanes organized by name:
   - `lanes`: Dictionary mapping lane/street names to waypoints
   - Use this to pick specific delivery coordinates

## Troubleshooting

### Model Not Found in Gazebo

```bash
# Check resource path inside container
docker compose exec osm2world bash -c 'echo $GZ_SIM_RESOURCE_PATH'

# Should include /workspace/models
# If not, export it:
docker compose exec osm2world bash -c 'export GZ_SIM_RESOURCE_PATH=/workspace/models && gz model --list'
```

### X11 Display Issues

```bash
# Check DISPLAY variable
echo $DISPLAY

# Allow Docker access
xhost +local:docker

# Verify X11 socket
ls -la /tmp/.X11-unix/
```

### Waypoints Not Extracted

```bash
# Check OSM file exists
ls -la data/bari.osm

# Run extraction manually
docker compose exec osm2world bash -c 'python3 /workspace/tools/extract_osm_waypoints.py /workspace/data/bari.osm -o /workspace/outputs/test.json -n 999999 -s 2.0 -m 5.0'
```

### Gazebo Crashes

```bash
# Ensure running as root with proper home directory
docker compose exec -u root osm2world bash -lc 'mkdir -p ~/.gz && gz sim /workspace/worlds/bari_world.world'
```

## Clean Up

When finished:
```bash
# Revoke X11 access
xhost -local:docker

# Stop container (optional)
docker compose down
```

## Next Steps

After conversion and verification:
1. Copy waypoints to fleet_drl workspace (Step 7 above)
2. Update `DEFAULT_WAYPOINTS_FILE` in training scripts
3. Ensure `GZ_SIM_RESOURCE_PATH` includes `map_osm_converter/models` in your ROS 2 workspace
4. Launch DRL training with the converted map

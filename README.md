# map_osm_converter

Convert OpenStreetMap (`.osm`) extracts into Gazebo-ready static models using OSM2World 0.4.0. Generates OBJ meshes, Gazebo models, world files, and extracts waypoints for DRL training.

## Setup

### 1. Prerequisites
- Docker and Docker Compose
- OSM2World 0.4.0 binaries
- An `.osm` map file (place in `./data/`)

### 2. Install OSM2World
1. Download `OSM2World-0.4.0-bin.zip` from: https://www.osm2world.org/download/
2. Extract to `./osm2world/` (should contain `OSM2World.jar`, `lib/`, `textures/`, etc.)

### 3. Build and Start Container
```bash
cd /home/studente/ackermann_sim/src/map_osm_converter
docker compose build
docker compose up -d
```

## Convert OSM to Gazebo Model

### Basic Usage
```bash
./convert_to_gazebo.sh <osm_file> <model_name> [world_name]
```

### Example: Convert bari.osm
```bash
./convert_to_gazebo.sh data/bari.osm bari_3d
```

**What it does:**
- Converts OSM to OBJ mesh via OSM2World with **enhanced graphics**:
  - ✅ **Terrain generation** - Realistic ground elevation
  - ✅ **Building colors** - Varied building appearances from OSM tags
  - ✅ **Vegetation** - Trees in forests and parks
  - ✅ **Textures** - Realistic materials for streets (asphalt), buildings (walls/windows), green areas (grass), sidewalks (concrete/paving)
  - ✅ **Billboards** - Optimized tree rendering
  - ✅ **Props** - Models and assets for enhanced visuals
- Computes vertex normals for Gazebo physics
- Creates Gazebo model in `models/<model_name>/` with all textures and assets
- **Automatically generates world file** in `worlds/<world_name>.sdf` (ROS 2 compatible)
  - For `bari_3d` model: Creates `bari_world.sdf` (compatible with ackermann-vehicle-gzsim-ros2)
  - Includes all required Gazebo Sim plugins (physics, sensors, scene broadcaster, user commands, IMU)
  - Model pose transformation matches existing `bari_world.sdf` structure (`-66 -275 0 1.5708 0 1.5708`)
  - Camera configured to follow robot (`saye::base_link::BaseVisual`)
  - Automatically copies to `ackermann-vehicle-gzsim-ros2/saye_description/worlds/` if available
  - **fleet_drl compatibility**: Model visual name `road_lane_street_visual` enables coordinate extraction
  - **Required**: Set `GZ_SIM_RESOURCE_PATH` to include `map_osm_converter/models` directory
- **Ackermann navigation optimization**:
  - ✅ **Strict filtering**: Filters narrow roads based on OSM width/lanes tags
    - **Minimum width**: 3.5m (required for Ackermann vehicle ~0.5m wide)
    - **Major roads**: Always included (motorway, trunk, primary, secondary, tertiary)
    - **Residential/Unclassified**: Only included if width ≥ 3.5m or lanes ≥ 1 with estimated width ≥ 3.5m
    - **Residential without width info**: Excluded (often too narrow)
  - ✅ **Separate navigable roads file**: Creates `*_navigable.json` and `*_navigable_lanes.json` files with ONLY roads suitable for Ackermann vehicles
  - ✅ **Color-coded roads** (visual approximation):
    - **Dark grey (0.15, 0.15, 0.15)**: ASPHALT/CONCRETE roads (major roads)
    - **Light grey (0.4, 0.4, 0.4)**: PAVING_STONE/PAVING/KERB (sidewalks, pedestrian areas)
    - **⚠️ Note**: Visual colors are approximate - OSM2World uses ASPHALT for all roads. Use `*_navigable.json` files for actual navigability!
  - ✅ **Road type filtering**: Includes motorway, trunk, primary, secondary, tertiary, unclassified (if wide), residential (if ≥ 3.5m)
  - 📍 **Use `*_navigable.json` files for DRL training** - these contain only roads where Ackermann robots should navigate!
- Extracts all waypoints to `outputs/<model_name>/<model_name>_waypoints.json`
- Organizes lanes/streets to `outputs/<model_name>/<model_name>_waypoints_lanes.json`

**Output Structure (organized by map name):**
```
outputs/
  └── <model_name>/
      ├── <model_name>.obj
      ├── <model_name>.obj.mtl
      ├── <model_name>_waypoints.json
      └── <model_name>_waypoints_lanes.json

models/
  └── <model_name>/
      ├── model.config
      ├── model.sdf
      └── meshes/
          ├── <model_name>.obj
          ├── <model_name>.obj.mtl
          ├── cc0textures/  (textures for roads, buildings, grass, etc.)
          ├── custom/  (custom textures: windows, glass, railway)
          ├── models/  (3D props: cars, trees, etc.)
          └── resources/  (shaders and resources)

worlds/
  └── <world_name>.sdf
```

## Visualize in Gazebo

### 1. Setup X11 Display (on host)
```bash
xhost +local:docker
export DISPLAY=:0
```

### 2. Launch Gazebo (GUI Mode)
```bash
docker compose exec \
  -u root \
  -e DISPLAY=$DISPLAY \
  -e XDG_RUNTIME_DIR=/tmp/osm2world_x11 \
  -e GZ_SIM_RESOURCE_PATH=/workspace/models:/opt/osm2world/models \
  osm2world \
  bash -lc 'mkdir -p ~/.gz && gz sim /workspace/worlds/<world_name>.sdf'
```

**Example for bari_3d (creates bari_world.sdf for ackermann project):**
```bash
docker compose exec \
  -u root \
  -e DISPLAY=$DISPLAY \
  -e XDG_RUNTIME_DIR=/tmp/osm2world_x11 \
  -e GZ_SIM_RESOURCE_PATH=/workspace/models:/opt/osm2world/models \
  osm2world \
  bash -lc 'mkdir -p ~/.gz && gz sim /workspace/worlds/bari_world.sdf'
```

**Note:** When converting `bari.osm` with model name `bari_3d`, the world file is automatically created as `worlds/bari_world.sdf` for compatibility with the ackermann-vehicle-gzsim-ros2 project. The world file is also automatically copied to `ackermann-vehicle-gzsim-ros2/saye_description/worlds/bari_world.sdf` if that directory exists.

### 3. Launch Gazebo (Headless Mode)
```bash
docker compose exec \
  -u root \
  -e GZ_SIM_RESOURCE_PATH=/workspace/models:/opt/osm2world/models \
  osm2world \
  bash -lc 'mkdir -p ~/.gz && gz sim /workspace/worlds/<world_name>.sdf -r -s'
```

### 4. Cleanup
```bash
xhost -local:docker
```

## Street-Based Spawning

The conversion automatically extracts street waypoints and positions the camera/spawn points on streets:

- **Camera**: Automatically positioned on a street for better initial view
- **Spawn Points**: Use waypoints file to get street coordinates for robot spawning

**Get spawn points for robots:**
```bash
# Get spawn configuration (JSON format)
python3 tools/get_street_spawn_points.py outputs/<model_name>/<model_name>_waypoints.json <num_robots>

# Example: Get 3 spawn points
python3 tools/get_street_spawn_points.py outputs/bari_3d/bari_3d_waypoints.json 3
```

The world file automatically includes a camera positioned on a street. For robot spawning, use the spawn points from the waypoints file.

## Output Files

### Model Files
- `models/<model_name>/model.sdf` - Gazebo model definition (uses OBJ materials for colors)
- `models/<model_name>/meshes/<model_name>.obj` - 3D mesh with textures, terrain, buildings, vegetation
- `models/<model_name>/meshes/<model_name>.obj.mtl` - Material definitions
- `models/<model_name>/meshes/cc0textures/` - Texture library (asphalt, grass, concrete, bricks, etc.)
- `models/<model_name>/meshes/custom/` - Custom textures (windows, glass, railway)
- `models/<model_name>/meshes/models/` - 3D props (cars, trees, etc.)
- `models/<model_name>/meshes/resources/` - Shaders and resources

**Visual Features:**
- 🛣️ **Streets**: Asphalt textures with road markings
- 🏢 **Buildings**: Textured walls with windows, varied colors
- 🌳 **Green Areas**: Grass textures, trees in parks/forests
- 🚶 **Sidewalks**: Concrete/paving stone textures
- 💧 **Water**: Water textures for rivers/lakes
- 🚗 **Props**: 3D models for enhanced realism

### World File
- `worlds/<world_name>.sdf` - Gazebo world file (ROS 2 compatible, SDF format)

### Waypoint Files (in `outputs/<model_name>/`)
- `<model_name>_waypoints.json` - All map coordinates (x, y, yaw)
- `<model_name>_waypoints_lanes.json` - Lanes/streets organized by name

## Quick Reference

**Convert bari.osm:**
```bash
./convert_to_gazebo.sh data/bari.osm bari_3d
```
*Note: The script automatically creates `worlds/bari_world.sdf` (not `bari_3d.sdf`) for ackermann project compatibility.*

**View in Gazebo:**
```bash
xhost +local:docker
export DISPLAY=:0
docker compose exec \
  -u root \
  -e DISPLAY=$DISPLAY \
  -e XDG_RUNTIME_DIR=/tmp/osm2world_x11 \
  -e GZ_SIM_RESOURCE_PATH=/workspace/models:/opt/osm2world/models \
  osm2world \
  bash -lc 'mkdir -p ~/.gz && gz sim /workspace/worlds/bari_world.sdf'
```

**Stop container:**
```bash
docker compose down
```

## Troubleshooting

- **OSM2World not found**: Ensure `OSM2World.jar` exists in `./osm2world/` and restart container
- **Gazebo crashes**: Use `-u root` flag and ensure `~/.gz` directory exists
- **Display issues**: Run `xhost +local:docker` and set `DISPLAY=:0`
- **Model not found**: Export `GZ_SIM_RESOURCE_PATH` to include `$(pwd)/models`
- **fleet_drl compatibility**: 
  - Ensure `GZ_SIM_RESOURCE_PATH` includes `~/ackermann_sim/src/map_osm_converter/models`
  - World file is automatically created as `worlds/bari_world.sdf` and copied to `ackermann-vehicle-gzsim-ros2/saye_description/worlds/bari_world.sdf`
  - Model visual name `road_lane_street_visual` enables coordinate extraction
  - For waypoint extraction, use `tools/extract_osm_waypoints.py` (more accurate than SDF-based extraction)

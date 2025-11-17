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
- Generates world file in `worlds/<world_name>.world`
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
  └── <world_name>.world
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
  osm2world \
  bash -lc 'mkdir -p ~/.gz && gz sim /workspace/worlds/<world_name>.world'
```

**Example for bari_world:**
```bash
docker compose exec \
  -u root \
  -e DISPLAY=$DISPLAY \
  -e XDG_RUNTIME_DIR=/tmp/osm2world_x11 \
  osm2world \
  bash -lc 'mkdir -p ~/.gz && gz sim /workspace/worlds/bari_3d.world'
```

### 3. Launch Gazebo (Headless Mode)
```bash
docker compose exec \
  -u root \
  osm2world \
  bash -lc 'mkdir -p ~/.gz && gz sim /workspace/worlds/<world_name>.world -r -s'
```

### 4. Cleanup
```bash
xhost -local:docker
```

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
- `worlds/<world_name>.world` - Gazebo world file

### Waypoint Files (in `outputs/<model_name>/`)
- `<model_name>_waypoints.json` - All map coordinates (x, y, yaw)
- `<model_name>_waypoints_lanes.json` - Lanes/streets organized by name

## Quick Reference

**Convert map:**
```bash
./convert_to_gazebo.sh data/bari.osm bari_3d bari_world
```

**View in Gazebo:**
```bash
xhost +local:docker
export DISPLAY=:0
docker compose exec -u root -e DISPLAY=$DISPLAY -e XDG_RUNTIME_DIR=/tmp/osm2world_x11 osm2world bash -lc 'mkdir -p ~/.gz && gz sim /workspace/worlds/bari_world.world'
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

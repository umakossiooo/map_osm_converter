# map_osm_converter

Convert OpenStreetMap (`.osm`) extracts into Gazebo-ready static models using the OSM2World 0.4.0 toolchain packaged in Docker. The workflow generates OBJ meshes, wraps them in Gazebo model metadata, fixes normals, and provides a launch-ready world file for Gazebo Harmonic.

## Prerequisites
- Docker and the Docker Compose plugin.
- OSM2World 0.4.0 binaries (downloaded separately, see below).
- An `.osm` map extract to convert (place it under `./data/`).

## Rehydrate the project
1. Download `OSM2World-0.4.0-bin.zip` from the official release:  
   https://github.com/tordanik/OSM2World/releases/download/0.4.0/OSM2World-0.4.0-bin.zip
2. Extract the archive into the project under `./osm2world/` (the folder should contain `OSM2World.jar`, `lib/`, `textures/`, etc.). The directory is git-ignored so you can replace it at any time.

## Build and start the container
```bash
docker compose build
docker compose up -d
```
The image installs OpenJDK 17, OSM2World’s runtime dependencies, Gazebo Harmonic (`gz sim`), and `assimp-utils`. The service stays idle (`tail -f /dev/null`) until you run a conversion or simulation.

## Convert an OSM file to a Gazebo model
```bash
./convert_to_gazebo.sh data/city.osm city_3d
```
- Generates `outputs/city_3d.obj` via OSM2World and recomputes face normals (required by Gazebo physics engines).
- Packages the assets under `models/city_3d/` with `model.config` and `model.sdf` (rotated to Gazebo’s Z-up frame).
- Creates a ready-to-launch world at `worlds/city_3d.world` using Bullet physics.

To make the model discoverable outside the container:
```bash
export GZ_SIM_RESOURCE_PATH=$GZ_SIM_RESOURCE_PATH:$(pwd)/models
```

### Fixing geometry normals manually
The conversion script calls the normal fixer automatically. To re-run it against an existing OBJ:
```bash
docker compose exec osm2world bash -lc \
  "python3 /workspace/tools/add_obj_normals.py \
    /workspace/outputs/city_3d.obj \
    /workspace/outputs/city_3d_with_normals.obj && \
   mv /workspace/outputs/city_3d_with_normals.obj /workspace/outputs/city_3d.obj"
```

## Simulate in Gazebo Harmonic (GUI)
1. Allow Docker to use your X11 display:
   ```bash
   xhost +local:docker
   ```
   Ensure `DISPLAY` is set in your shell (e.g., `export DISPLAY=:0`).
2. Launch Gazebo from inside the container (run as `root` so Gazebo finds a valid home directory):
   ```bash
   docker compose up -d osm2world
   docker compose exec \
     -u root \
     -e DISPLAY=$DISPLAY \
     -e XDG_RUNTIME_DIR=/tmp/osm2world_x11 \
     osm2world \
     bash -lc 'mkdir -p ~/.gz && gz sim /workspace/worlds/city_3d.world'
   ```
   For headless mode append `-r -s` to the `gz sim` command. To load just the model:
   ```bash
   docker compose exec \
     -u root \
     -e DISPLAY=$DISPLAY \
     -e XDG_RUNTIME_DIR=/tmp/osm2world_x11 \
     osm2world \
     bash -lc 'mkdir -p ~/.gz && gz sim /workspace/models/city_3d/model.sdf'
   ```
3. When finished, revoke display access with `xhost -local:docker`.

## Clean up
```bash
docker compose down
```
This stops and removes the helper container. Bring it back with `docker compose up -d` whenever you need to convert more maps.

## Troubleshooting
- **`❌ OSM2World did not produce ...`** — the conversion failed because the input `.osm` has invalid/self-intersecting polygons. Inspect the warnings in the log (relation IDs) and clean the data (e.g., via JOSM) or clip the map to a simpler region.
- **Gazebo crashes at startup** — make sure you use the `docker compose exec -u root ... bash -lc 'mkdir -p ~/.gz && gz sim ...'` command shown above so the logger can create its working directory.
- **Outputs owned by root** — if you ran the container without the compose file, fix permissions once:  
  `docker compose exec -u root osm2world chown -R $(id -u):$(id -g) /workspace/outputs /workspace/models`

Happy mapping!

#!/usr/bin/env bash
# Copy OSM2World textures to model directory and update MTL paths

MODEL_DIR="$1"
MESH_DIR="$MODEL_DIR/meshes"
OSM2WORLD_TEXTURES="/opt/osm2world/textures"

if [ ! -d "$MESH_DIR" ]; then
    echo "⚠️  Mesh directory not found: $MESH_DIR"
    exit 1
fi

# Copy common texture directories from OSM2World
if [ -d "$OSM2WORLD_TEXTURES" ]; then
    echo "📸 Copying OSM2World textures to model..."
    
    # Copy cc0textures (common textures for roads, buildings, etc.)
    if [ -d "$OSM2WORLD_TEXTURES/cc0textures" ]; then
        cp -r "$OSM2WORLD_TEXTURES/cc0textures" "$MESH_DIR/" 2>/dev/null || true
    fi
    
    # Copy custom textures
    if [ -d "$OSM2WORLD_TEXTURES/custom" ]; then
        cp -r "$OSM2WORLD_TEXTURES/custom" "$MESH_DIR/" 2>/dev/null || true
    fi
    
    # Copy individual texture files
    find "$OSM2WORLD_TEXTURES" -maxdepth 1 -type f \( -name "*.jpg" -o -name "*.png" -o -name "*.JPG" -o -name "*.PNG" \) \
        -exec cp {} "$MESH_DIR/" \; 2>/dev/null || true
    
    echo "✅ Textures copied to $MESH_DIR/"
else
    echo "⚠️  OSM2World textures directory not found at $OSM2WORLD_TEXTURES"
fi


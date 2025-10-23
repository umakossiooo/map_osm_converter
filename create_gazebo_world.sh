#!/usr/bin/env bash
set -euo pipefail

MODEL_NAME=${1:-city_3d}
WORLD_NAME=${2:-$MODEL_NAME}
WORLD_DIR=${3:-worlds}

mkdir -p "$WORLD_DIR"

WORLD_PATH="$WORLD_DIR/$WORLD_NAME.world"

cat <<EOF > "$WORLD_PATH"
<?xml version="1.0" ?>
<sdf version="1.9">
  <world name="${WORLD_NAME}_world">
    <gravity>0 0 -9.81</gravity>
    <physics type="bullet">
      <max_step_size>0.001</max_step_size>
      <real_time_update_rate>1000</real_time_update_rate>
    </physics>
    <include>
      <uri>model://$MODEL_NAME</uri>
    </include>
  </world>
</sdf>
EOF

echo "🌍 World '$WORLD_NAME' created at $WORLD_PATH referencing model '$MODEL_NAME'."

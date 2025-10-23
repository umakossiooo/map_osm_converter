# Dockerfile for OSM -> 3D conversion with OSM2World 0.4.0 and Gazebo Harmonic
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive \
    GZ_SIM_RESOURCE_PATH=/workspace/models

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      bash \
      ca-certificates \
      gnupg \
      lsb-release \
      wget \
      openjdk-17-jre \
      assimp-utils && \
    wget https://packages.osrfoundation.org/gazebo.gpg -O /usr/share/keyrings/gazebo-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/gazebo-archive-keyring.gpg] http://packages.osrfoundation.org/gazebo/ubuntu $(lsb_release -cs) main" > /etc/apt/sources.list.d/gazebo-stable.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
      gz-harmonic && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

# Helper script to run OSM2World conversion inside the container
RUN echo '#!/usr/bin/env bash' > /usr/local/bin/osm2dae && \
    echo 'set -euo pipefail' >> /usr/local/bin/osm2dae && \
    echo 'OSM_IN="${1:-data/city.osm}"' >> /usr/local/bin/osm2dae && \
    echo 'OUT="${2:-outputs/city.obj}"' >> /usr/local/bin/osm2dae && \
    echo 'mkdir -p "$(dirname "$OUT")"' >> /usr/local/bin/osm2dae && \
    echo 'java -Xms512m -Xmx4g -jar /opt/osm2world/OSM2World.jar -i "$OSM_IN" -o "$OUT"' >> /usr/local/bin/osm2dae && \
    chmod +x /usr/local/bin/osm2dae

CMD ["bash", "-lc", "echo 'Ready. Mount ./osm2world, ./data, ./models, ./outputs, ./worlds and ./tools. Run conversion with: osm2dae data/city.osm outputs/city.obj' && tail -f /dev/null"]

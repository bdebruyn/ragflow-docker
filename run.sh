#!/usr/bin/env bash
set -euo pipefail

CALLER_DIR="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd "${SCRIPT_DIR}"

export COMPOSE_PROJECT_NAME="ragflow"
export RAGFLOW_PROJECT_DIR="${SCRIPT_DIR}"

image="ragflow-debian"
container="ragflow_dev"
cpus=$(($(sysctl -n hw.physicalcpu) - 1))

# Only start compose services if not already running
if ! docker compose ps --status running | grep -q "ragflow-elasticsearch"; then
    echo "Starting backing services..."
    docker compose up -d elasticsearch redis mysql minio
    echo "Waiting for backing services to be healthy..."
    # Poll Docker's own healthcheck status — no need for curl/mysqladmin inside containers
    for svc in ragflow-elasticsearch-1 ragflow-mysql-1 ragflow-redis-1; do
        echo -n "  Waiting for ${svc}..."
        until [ "$(docker inspect --format='{{.State.Health.Status}}' ${svc} 2>/dev/null)" = 'healthy' ]; do
            sleep 3
            echo -n '.'
        done
        echo ' healthy'
    done
    echo "All backing services are healthy."
else
    echo "Backing services already running, skipping..."
fi

# Only create the app container if it doesn't already exist
if docker ps -a --format '{{.Names}}' | grep -q "^${container}$"; then
    echo "Container ${container} already exists, attaching..."
    docker start "${container}" 2>/dev/null || true
else
    echo "Starting container ${container} ..."
    docker rm -f "${container}" 2>/dev/null || true

    docker create -it \
        --name "${container}" \
        -p 80:80 \
        -p 443:443 \
        -p 9380:9380 \
        --network ragflow_default \
        --cpuset-cpus="0-${cpus}" \
        --env ES_HOST=elasticsearch \
        --env REDIS_HOST=redis \
        --env MYSQL_HOST=mysql \
        --env MINIO_HOST=minio:9000 \
        --env CONTAINER_NAME="${container}" \
        --env IMAGE_NAME="${image}" \
        -v "${HOME}/.gitconfig:/home/ragflow/.gitconfig:ro" \
        -v "${HOME}/.ssh/id_rsa:/home/ragflow/.ssh/id_rsa:ro" \
        -v "${CALLER_DIR}:/workspace:delegated" \
        -v "/tmp:/tmp:delegated" \
        --hostname "$(hostname)" \
        --cap-add=ALL \
        --cap-add=sys_nice \
        --ulimit rtprio=99 \
        --privileged \
        "${image}"

    docker start "${container}"
fi

docker exec -it "${container}" /bin/bash

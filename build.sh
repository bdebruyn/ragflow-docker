#!/usr/bin/env bash
set -euo pipefail

dockerImageName="ragflow-debian"
dockerBase="debian:bookworm-slim"
cacheArg=""   # set to "--no-cache" to force a clean build

# Optional: use BuildKit layer cache
# cacheArg="--cache-from ${dockerImageName}:latest"
# cacheArg="--no-cache"

docker build \
    ${cacheArg} \
    --ssh default \
    -t "${dockerImageName}" \
    --build-arg Base="${dockerBase}" \
    --build-arg UID="$(id -u)" \
    --build-arg GID="$(id -g)" \
    --build-arg Name="${dockerImageName}" \
    .

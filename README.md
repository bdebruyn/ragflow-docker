# RAGflow Development Container — macOS (i9)

A containerised RAGflow development environment designed to run on macOS with an Intel i9 processor. The setup wraps RAGflow and all of its backing services in Docker, managed through a small set of shell scripts accessible system-wide via `/usr/local/bin`.

---

## Overview

[RAGflow](https://github.com/infiniflow/ragflow) is an open-source RAG (Retrieval-Augmented Generation) engine. Running it in a container isolates its many dependencies (Elasticsearch, MySQL, Redis, MinIO) from the host machine and lets you bring the full stack up or down with a single command from any directory.

The app container is built on **Debian Bookworm Slim**, keeping the base image lean while remaining compatible with RAGflow's Python and native library requirements.

---

## Architecture

```
macOS Host (i9)
└── Docker Desktop
    ├── ragflow_app          ← Debian bookworm-slim + RAGflow (your workspace)
    ├── ragflow-elasticsearch-1   ← Search & vector index backend
    ├── ragflow-mysql-1           ← Relational metadata store
    ├── ragflow-redis-1           ← Cache & task queue
    └── ragflow-minio-1           ← Object storage (documents, models)
```

All services communicate over an isolated Docker network (`ragflow_default`). Only the RAGflow app ports are exposed to the host — backing services are intentionally kept internal.

### Exposed Ports

| Port | Service |
|------|---------|
| `80` | RAGflow HTTP |
| `443` | RAGflow HTTPS |
| `9380` | RAGflow API |

---

## Prerequisites

- macOS with Docker Desktop installed
- Intel i9 processor (the scripts detect physical CPU count via `sysctl`)
- SSH key at `~/.ssh/id_rsa` (mounted read-only into the container)
- `~/.gitconfig` present on the host

---

## Project Structure

```
ragflow-docker/
├── Dockerfile              # Debian-based RAGflow image
├── docker-compose.yaml     # Backing services (ES, MySQL, Redis, MinIO)
├── run.sh                  # Build, start, and attach to the dev container
├── docker-down.sh          # Gracefully stop all services
└── config/                 # Project config mounted into /workspace/config
```

---

## Installation

Clone the repository and create the system-wide command links:

```bash
git clone <your-repo-url> ragflow-docker
cd ragflow-docker

chmod +x run.sh docker-down.sh

sudo ln -s "$(pwd)/run.sh"          /usr/local/bin/ragflow-run
sudo ln -s "$(pwd)/docker-down.sh"  /usr/local/bin/ragflow-down
```

---

## Usage

### Start the environment

```bash
ragflow-run
```

Run this from **any directory**. The directory you invoke it from is mounted as `/workspace` inside the container, so your current project is immediately available. Backing services that are already running are left untouched.

### Stop the environment

```bash
ragflow-down
```

Removes all containers and the Docker network. Named volumes (your ES indices, MySQL data, MinIO objects) are **preserved** so data survives across restarts.

### Wipe all data (clean slate)

```bash
cd ~/path/to/ragflow-docker
docker compose down -v
```

The `-v` flag removes volumes in addition to containers. Use this only when you want to reset RAGflow's state entirely.

---

## How It Works

### `run.sh`

1. Captures the **caller's working directory** (`CALLER_DIR`) before changing into the script's own directory — this is what gets mounted as `/workspace`.
2. Changes into the `ragflow-docker/` directory so Docker Compose can find `docker-compose.yaml`.
3. Sets `COMPOSE_PROJECT_NAME=ragflow` so all resources are consistently namespaced regardless of the folder name on disk.
4. Runs `docker compose down` to cleanly remove any previously stopped containers (preventing port allocation conflicts on restart).
5. Starts backing services (`elasticsearch`, `mysql`, `redis`, `minio`) via Compose.
6. Checks whether the app container already exists — creates it if not, starts it if so.
7. Attaches an interactive shell (`docker exec -it ... /bin/bash`).

### `docker-down.sh`

Navigates to its own directory, sets the project name, and runs `docker compose down`. Scoped strictly to the `ragflow` project — no other Docker Compose projects on your machine are affected.

### Volume strategy

| Volume | Contents | Survives `down` | Survives `down -v` |
|--------|----------|-----------------|-------------------|
| `ragflow_es_data` | Elasticsearch indices | ✅ | ❌ |
| `ragflow_mysql_data` | RAGflow metadata | ✅ | ❌ |
| `ragflow_redis_data` | Cache / queues | ✅ | ❌ |
| `ragflow_minio_data` | Uploaded documents | ✅ | ❌ |

---

## Features

- **Invoke from anywhere** — `ragflow-run` mounts whichever directory you're in as `/workspace`, so you never need to `cd` into the project first.
- **Idempotent startup** — re-running `ragflow-run` is safe; it tears down stale containers cleanly before recreating them without touching persistent data.
- **Scoped teardown** — `ragflow-down` only affects the ragflow project; unrelated Compose stacks on the same machine are untouched.
- **Host identity passthrough** — your `~/.gitconfig` and `~/.ssh/id_rsa` are mounted read-only so Git and SSH work inside the container as they do on your Mac.
- **Shared config** — `ragflow-docker/config/` is always available at `/workspace/config` regardless of which directory you launched from.
- **CPU-aware** — container is allocated all physical cores minus one (`sysctl hw.physicalcpu - 1`), leaving one core free for macOS.
- **Privileged capabilities** — `--cap-add=ALL`, `--cap-add=sys_nice`, and `--ulimit rtprio=99` are set for workloads that require elevated scheduling priority.
- **Debian base** — `debian:bookworm-slim` keeps the image minimal while providing full `apt` access for adding tools as needed.

---

## macOS Notes

- `--cpuset-cpus` is passed but **has no effect on macOS** — Docker Desktop does not expose host CPU topology to containers. It is kept for forward compatibility if the stack is ever moved to a Linux host.
- GPU / Metal acceleration is not available inside Docker containers on macOS. For LLM inference acceleration, run [Ollama](https://ollama.com) on the host and point RAGflow at `host.docker.internal`.
- MinIO and Elasticsearch ports are **not** bound to the host to avoid conflicts with other local services. If you need direct host access (e.g. for the MinIO console), temporarily re-enable the relevant `ports:` entries in `docker-compose.yaml`.

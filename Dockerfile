ARG Base=debian:bookworm-slim
ARG RAGFLOW_VERSION=main

# ════════════════════════════════════════════════════════════════════════════
# Stage 1 — Frontend builder
# Isolated Node stage so the Vite build has the full memory budget to itself
# and doesn't compete with Python deps in the main image.
# ════════════════════════════════════════════════════════════════════════════
FROM node:20-slim AS frontend-builder

ARG RAGFLOW_VERSION

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    && rm -rf /var/lib/apt/lists/*

# Sparse-clone just the web/ subtree — no need to pull the whole repo
RUN git clone --depth=1 --branch ${RAGFLOW_VERSION} \
    --filter=blob:none --sparse \
    https://github.com/infiniflow/ragflow.git /ragflow \
    && cd /ragflow && git sparse-checkout set web docs

WORKDIR /ragflow/web

# Vite needs ~2.5 GB for this codebase; 3 GB gives headroom, semi-space tuned down to reduce GC pressure
ENV NODE_OPTIONS="--max-old-space-size=4096 --max-semi-space-size=64"
RUN npm install && npm run build


# ════════════════════════════════════════════════════════════════════════════
# Stage 2 — Main runtime image
# ════════════════════════════════════════════════════════════════════════════
FROM ${Base}

ARG UID=1000
ARG GID=1000
ARG Name=ragflow
ARG RAGFLOW_VERSION

# ── System deps ───────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Core tools
    ca-certificates \
    curl \
    wget \
    git \
    gnupg \
    lsb-release \
    procps \
    sudo \
    pkg-config \
    unzip \
    # Build tools
    build-essential \
    libssl-dev \
    libffi-dev \
    # Python runtime
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    # jemalloc — required by RAGflow task executor
    libjemalloc-dev \
    # RAGflow OCR / vision / document libs
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    libmagic1 \
    poppler-utils \
    tesseract-ocr \
    libreoffice \
    # nginx — serves the frontend and proxies to ragflow_server
    nginx \
    && rm -rf /var/lib/apt/lists/*

# ── uv (fast Python package manager used by RAGflow) ─────────────────────────
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# ── Clone RAGflow source ──────────────────────────────────────────────────────
RUN git clone --depth=1 --branch ${RAGFLOW_VERSION} \
    https://github.com/infiniflow/ragflow.git /ragflow

WORKDIR /ragflow

# ── Install Python dependencies via uv ───────────────────────────────────────
# Creates /ragflow/.venv with all project deps
ENV UV_PROJECT_ENVIRONMENT=/ragflow/.venv
RUN uv sync --python 3.12 --no-dev

# ── Download model/NLP assets required at runtime ────────────────────────────
RUN uv run download_deps.py

# ── Copy pre-built frontend from stage 1 ─────────────────────────────────────
# Node never runs in this stage — no memory pressure from the Vite build
COPY --from=frontend-builder /ragflow/web/dist /ragflow/web/dist

# ── Configure nginx ──────────────────────────────────────────────────────────
# entrypoint.sh calls /usr/sbin/nginx but doesn't copy config files first.
RUN mkdir -p /etc/nginx/conf.d /var/log/nginx && \
    cp /ragflow/docker/nginx/nginx.conf /etc/nginx/nginx.conf && \
    cp /ragflow/docker/nginx/ragflow.conf /etc/nginx/conf.d/ragflow.conf && \
    cp /ragflow/docker/nginx/proxy.conf /etc/nginx/proxy.conf && \
    rm -f /etc/nginx/sites-enabled/default

# ── Stage service_conf template where entrypoint.sh expects it ──────────────
# entrypoint.sh reads from /ragflow/conf/service_conf.yaml.template, not docker/
RUN mkdir -p /ragflow/conf && \
    cp /ragflow/docker/service_conf.yaml.template /ragflow/conf/service_conf.yaml.template


# ── Download NLTK data ───────────────────────────────────────────────────────
# Download all corpora RAGflow's tokenizer/lemmatizer/stemmer pipeline requires.
RUN /ragflow/.venv/bin/python -c "\
import nltk; \
nltk.download('punkt_tab'); \
nltk.download('averaged_perceptron_tagger_eng'); \
nltk.download('wordnet'); \
nltk.download('omw-1.4'); \
nltk.download('stopwords'); \
nltk.download('words'); \
"

# ── Extra runtime libs (added last to preserve cache of expensive layers above) ──
# libgl1 is required by opencv-python (cv2) which is imported by the task executor.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 \
    && rm -rf /var/lib/apt/lists/*

# ── Create user matching host UID/GID ─────────────────────────────────────────
# macOS UIDs (e.g. 501) are below Debian's default UID_MIN 1000 — lower the floor.
# Use --non-unique so we can reuse a GID already claimed by a system group (e.g. GID 20 = dialout).
# Reference UID/GID numbers in chown rather than names to avoid lookup failures.
RUN sed -i 's/^UID_MIN.*/UID_MIN 100/' /etc/login.defs \
    && sed -i 's/^GID_MIN.*/GID_MIN 100/' /etc/login.defs \
    && groupadd --non-unique -g ${GID} ${Name} 2>/dev/null || true \
    && useradd -m -u ${UID} -g ${GID} -s /bin/bash -G sudo ${Name} \
    && echo "${Name} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
    && chown -R ${UID}:${GID} /ragflow

# ── Runtime environment ───────────────────────────────────────────────────────
ENV PATH="/ragflow/.venv/bin:${PATH}" \
    PYTHONPATH="/ragflow" \
    # Tell task_executor to use jemalloc for reduced memory fragmentation
    JEMALLOC_PATH="/usr/lib/x86_64-linux-gnu/libjemalloc.so"

WORKDIR /ragflow

EXPOSE 80 443 9380

# entrypoint.sh starts nginx, ragflow_server, and task_executor then waits.
# This is PID 1 — the container stays alive as long as entrypoint.sh is running.
CMD ["/ragflow/docker/entrypoint.sh"]

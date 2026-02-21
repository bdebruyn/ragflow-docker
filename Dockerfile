ARG Base=debian:bookworm-slim

FROM ${Base}

ARG UID=1000
ARG GID=1000
ARG Name=ragflow

# ── System deps ──────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    git \
    gnupg \
    lsb-release \
    procps \
    sudo \
    build-essential \
    libssl-dev \
    libffi-dev \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    # Python
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    # Needed by RAGflow OCR / vision libs
    libmagic1 \
    poppler-utils \
    tesseract-ocr \
    libreoffice \
    && rm -rf /var/lib/apt/lists/*

# ── Create user matching host UID/GID ────────────────────────────────────────
RUN groupadd -g ${GID} ${Name} 2>/dev/null || true && \
    useradd -m -u ${UID} -g ${GID} -s /bin/bash -G sudo ${Name} && \
    echo "${Name} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# ── Python venv for RAGflow ───────────────────────────────────────────────────
ENV VIRTUAL_ENV=/opt/ragflow-venv
RUN python3 -m venv ${VIRTUAL_ENV}
ENV PATH="${VIRTUAL_ENV}/bin:${PATH}"

# ── Install RAGflow ───────────────────────────────────────────────────────────
# Option A: install from PyPI (ragflow-sdk is the client; full server below)
# Option B: clone and install the full server
RUN pip install --upgrade pip && \
    pip install ragflow-sdk

# For the FULL server (comment out the pip line above and use this instead):
# RUN git clone https://github.com/infiniflow/ragflow.git /opt/ragflow && \
#     cd /opt/ragflow && \
#     pip install -r requirements.txt

WORKDIR /workspace

USER ${Name}

EXPOSE 80 443 9380

CMD ["/bin/bash"]

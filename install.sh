#!/usr/bin/env bash
set -euo pipefail

REPO="${RAG_DIST_REPO:-comma-separated/ai-rag-dist}"
VERSION="${RAG_VERSION:-latest}"
INSTANCE="${RAG_INSTANCE:-default}"

RAG_USER="${RAG_USER:-rag}"
RAG_GROUP="${RAG_GROUP:-rag}"
RAG_ROOT_DIR="${RAG_ROOT_DIR:-/opt/rag}"
RAG_ENV_ROOT="${RAG_ENV_ROOT:-/etc/rag}"
RAG_DATA_ROOT="${RAG_DATA_ROOT:-/var/lib/rag}"
RAG_KNOWLEDGE_ROOT="${RAG_KNOWLEDGE_ROOT:-${RAG_ROOT_DIR}/knowledge}"

RAG_BIN_PATH="${RAG_BIN_PATH:-${RAG_ROOT_DIR}/bin/rag}"
RAG_ENV_DIR="${RAG_ENV_ROOT}/${INSTANCE}"
RAG_ENV_FILE="${RAG_ENV_DIR}/rag.env"
RAG_SERVICE_PATH="/etc/systemd/system/rag@.service"

RAG_HTTP_ADDR="${RAG_HTTP_ADDR:-127.0.0.1:8080}"
RAG_LOG_LEVEL="${RAG_LOG_LEVEL:-info}"
RAG_VECTORSTORE_TYPE="${RAG_VECTORSTORE_TYPE:-file}"
RAG_VECTORSTORE_PATH="${RAG_VECTORSTORE_PATH:-${RAG_DATA_ROOT}/${INSTANCE}/rag.chunks.jsonl}"
RAG_API_KEY="${RAG_API_KEY:-}"
RAG_LICENSE="${RAG_LICENSE:-}"

OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
OLLAMA_MODEL_CHAT="${OLLAMA_MODEL_CHAT:-qwen2.5:7b}"
OLLAMA_MODEL_EMBEDDING="${OLLAMA_MODEL_EMBEDDING:-yxchia/multilingual-e5-base}"

OVERWRITE_ENV="${RAG_OVERWRITE_ENV:-false}"

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "This installer must run as root. Use sudo." >&2
    exit 1
  fi
}

detect_asset() {
  local arch
  arch="$(uname -m)"

  case "$arch" in
    x86_64|amd64)
      echo "rag_linux_amd64"
      ;;
    aarch64|arm64)
      echo "rag_linux_arm64"
      ;;
    *)
      echo "Unsupported CPU architecture: $arch" >&2
      exit 1
      ;;
  esac
}

download_url() {
  local asset="$1"

  if [ "$VERSION" = "latest" ]; then
    echo "https://github.com/${REPO}/releases/latest/download/${asset}"
  else
    echo "https://github.com/${REPO}/releases/download/${VERSION}/${asset}"
  fi
}

install_prerequisites() {
  command -v curl >/dev/null 2>&1 && return

  if command -v apt-get >/dev/null 2>&1; then
    apt-get update
    apt-get install -y curl ca-certificates
    return
  fi

  echo "curl is required. Install curl and rerun this script." >&2
  exit 1
}

ensure_user_and_dirs() {
  getent group "$RAG_GROUP" >/dev/null || groupadd --system "$RAG_GROUP"
  id "$RAG_USER" >/dev/null 2>&1 || useradd --system --no-create-home --gid "$RAG_GROUP" --shell /usr/sbin/nologin "$RAG_USER"

  install -d -m 0755 "$RAG_ROOT_DIR" "${RAG_ROOT_DIR}/bin" "$RAG_ENV_ROOT" "$RAG_DATA_ROOT" "$RAG_KNOWLEDGE_ROOT"
  install -d -m 0750 -o "$RAG_USER" -g "$RAG_GROUP" "${RAG_DATA_ROOT}/${INSTANCE}" "${RAG_KNOWLEDGE_ROOT}/${INSTANCE}"
  install -d -m 0750 -o root -g "$RAG_GROUP" "$RAG_ENV_DIR"
}

install_binary() {
  local asset="$1"
  local bin_url checksum_url tmp_dir tmp_bin tmp_checksums expected actual

  bin_url="$(download_url "$asset")"
  checksum_url="$(download_url "checksums.txt")"
  tmp_dir="$(mktemp -d)"
  tmp_bin="${tmp_dir}/${asset}"
  tmp_checksums="${tmp_dir}/checksums.txt"

  echo "Downloading ${bin_url}"
  curl -fsSL "$bin_url" -o "$tmp_bin"

  if curl -fsSL "$checksum_url" -o "$tmp_checksums"; then
    expected="$(awk -v name="$asset" '$2 == name { print $1 }' "$tmp_checksums" | head -n 1)"
    if [ -n "$expected" ]; then
      actual="$(sha256sum "$tmp_bin" | awk '{ print $1 }')"
      if [ "$expected" != "$actual" ]; then
        echo "Checksum mismatch for ${asset}" >&2
        echo "Expected: ${expected}" >&2
        echo "Actual:   ${actual}" >&2
        exit 1
      fi
      echo "Checksum verified"
    else
      echo "checksums.txt downloaded, but ${asset} was not listed; skipping checksum verification"
    fi
  else
    echo "checksums.txt was not available; skipping checksum verification"
  fi

  install -m 0755 -o root -g root "$tmp_bin" "$RAG_BIN_PATH"
  rm -rf "$tmp_dir"
}

write_env() {
  if [ -f "$RAG_ENV_FILE" ] && [ "$OVERWRITE_ENV" != "true" ]; then
    echo "Keeping existing ${RAG_ENV_FILE}. Set RAG_OVERWRITE_ENV=true to replace it."
    return
  fi

  cat > "$RAG_ENV_FILE" <<EOF
KNOWLEDGE_PATH=${RAG_KNOWLEDGE_ROOT}/${INSTANCE}
OLLAMA_MODEL_CHAT=${OLLAMA_MODEL_CHAT}
OLLAMA_MODEL_EMBEDDING=${OLLAMA_MODEL_EMBEDDING}
OLLAMA_URL=${OLLAMA_URL}
QDRANT_API_KEY=
QDRANT_COLLECTION=rag_chunks
QDRANT_URL=
RAG_API_KEY=${RAG_API_KEY}
RAG_ASK_DEFAULT_STREAM=
RAG_ASK_DEFAULT_THINK=
RAG_CHUNK_INCLUDE_HEADING=true
RAG_CHUNK_MAX_CHARS=2000
RAG_CHUNK_MAX_WORDS=200
RAG_CHUNK_MIN_WORDS=0
RAG_CHUNK_OVERLAP_WORDS=20
RAG_EMBED_MAX_TOKENS=512
RAG_HISTORY_MAX_TURNS=6
RAG_HTTP_ADDR=${RAG_HTTP_ADDR}
RAG_INGEST_STRICT=false
RAG_LICENSE=${RAG_LICENSE}
RAG_LOG_LEVEL=${RAG_LOG_LEVEL}
RAG_RELATED_DOCS_LIMIT=3
RAG_SIMILARITY_THRESHOLD=0.2
RAG_SOURCES_LINKS_LIMIT=3
RAG_TOPK=5
RAG_VECTORSTORE_PATH=${RAG_VECTORSTORE_PATH}
RAG_VECTORSTORE_TYPE=${RAG_VECTORSTORE_TYPE}
EOF

  chown root:"$RAG_GROUP" "$RAG_ENV_FILE"
  chmod 0640 "$RAG_ENV_FILE"
}

write_systemd_unit() {
  cat > "$RAG_SERVICE_PATH" <<EOF
[Unit]
Description=RAG instance %i
After=network.target

[Service]
Type=simple
User=${RAG_USER}
Group=${RAG_GROUP}
EnvironmentFile=${RAG_ENV_ROOT}/%i/rag.env
EnvironmentFile=-${RAG_ENV_ROOT}/%i/rag.vault.env
WorkingDirectory=${RAG_ROOT_DIR}
ExecStart=${RAG_BIN_PATH} serve
Restart=always
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=true
ReadWritePaths=${RAG_DATA_ROOT} ${RAG_KNOWLEDGE_ROOT}

[Install]
WantedBy=multi-user.target
EOF
}

start_service() {
  systemctl daemon-reload
  systemctl enable --now "rag@${INSTANCE}.service"
}

main() {
  require_root
  install_prerequisites

  local asset
  asset="$(detect_asset)"

  ensure_user_and_dirs
  install_binary "$asset"
  write_env
  write_systemd_unit
  start_service

  echo
  echo "RAG was installed successfully."
  echo "Instance: ${INSTANCE}"
  echo "Binary: ${RAG_BIN_PATH}"
  echo "Env: ${RAG_ENV_FILE}"
  echo "Service: rag@${INSTANCE}.service"
  echo
  echo "Check status with:"
  echo "  systemctl status rag@${INSTANCE}.service"
}

main "$@"

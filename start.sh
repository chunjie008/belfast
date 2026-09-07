#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP="belfast"
CONFIG="${CONFIG:-server.toml}"
BIN="bin/${APP}"
PID_FILE="run/${APP}.pid"
LOG_DIR="logs"
LOG_FILE="${LOG_DIR}/${APP}.log"

if command -v go >/dev/null 2>&1; then
  GO="go"
elif [ -x /home/water/go/bin/go ]; then
  GO="/home/water/go/bin/go"
else
  echo "[start] go toolchain not found, set GO=/path/to/go" >&2
  exit 1
fi

if [ -f "${PID_FILE}" ]; then
  pid="$(cat "${PID_FILE}")"
  if kill -0 "${pid}" 2>/dev/null; then
    echo "[start] ${APP} already running (pid ${pid})"
    exit 0
  fi
  echo "[start] removing stale pid file"
  rm -f "${PID_FILE}"
fi

mkdir -p bin run "${LOG_DIR}"

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  echo "[start] building ${APP}"
  "${GO}" build -o "${BIN}" ./cmd/belfast
else
  echo "[start] SKIP_BUILD=1, using existing ${BIN}"
fi

if [ ! -x "${BIN}" ]; then
  echo "[start] binary not found: ${BIN}" >&2
  exit 1
fi

echo "[start] launching ${APP}"
nohup "${BIN}" --config "${CONFIG}" >> "${LOG_FILE}" 2>&1 &
pid=$!
echo "${pid}" > "${PID_FILE}"

wait_port="$(awk '
  /^\[api\]/ { section="api"; next }
  /^\[[^]]+\]/ { section="other" }
  section == "api" && $1 == "port" { gsub(/[^0-9]/, "", $NF); print $NF; exit }
' "${CONFIG}" 2>/dev/null || true)"

if [ -z "${wait_port}" ]; then
  wait_port="$(awk '
    /^\[belfast\]/ { section="belfast"; next }
    /^\[[^]]+\]/ { section="other" }
    section == "belfast" && $1 == "port" { gsub(/[^0-9]/, "", $NF); print $NF; exit }
  ' "${CONFIG}" 2>/dev/null || true)"
fi

if [ -n "${wait_port}" ]; then
  echo "[start] waiting for ${APP} on port ${wait_port}"
  deadline=$((SECONDS + 120))
  while [ "${SECONDS}" -lt "${deadline}" ]; do
    if (echo > /dev/tcp/127.0.0.1/"${wait_port}") 2>/dev/null; then
      echo "[start] ${APP} started (pid ${pid})"
      echo "[start] log: ${LOG_FILE}"
      exit 0
    fi
    if ! kill -0 "${pid}" 2>/dev/null; then
      echo "[start] ${APP} exited during startup, see ${LOG_FILE}" >&2
      exit 1
    fi
    sleep 1
  done
  echo "[start] ${APP} did not open port ${wait_port} in time, see ${LOG_FILE}" >&2
  exit 1
fi

echo "[start] ${APP} launched (pid ${pid})"
echo "[start] log: ${LOG_FILE}"

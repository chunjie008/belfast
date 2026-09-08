#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP="belfast"
CONFIG="${CONFIG:-server.toml}"
BIN="bin/${APP}"
PID_FILE="run/${APP}.pid"
LOG_DIR="logs"
LOG_FILE="${LOG_DIR}/${APP}.log"

GATEWAY="gateway"
GW_CONFIG="${GATEWAY_CONFIG:-gateway.toml}"
GW_BIN="bin/${GATEWAY}"
GW_PID_FILE="run/${GATEWAY}.pid"
GW_LOG_FILE="${LOG_DIR}/${GATEWAY}.log"
SKIP_GATEWAY="${SKIP_GATEWAY:-0}"

if command -v go >/dev/null 2>&1; then
  GO="go"
elif [ -x /home/water/go/bin/go ]; then
  GO="/home/water/go/bin/go"
else
  echo "[start] go toolchain not found, set GO=/path/to/go" >&2
  exit 1
fi

if [ "${SKIP_GATEWAY}" != "1" ] && [ ! -f "${GW_CONFIG}" ]; then
  echo "[start] gateway config not found: ${GW_CONFIG} (set SKIP_GATEWAY=1 to run ${APP} only)" >&2
  exit 1
fi

check_stale_pid() {
  local name="$1" pid_file="$2"
  if [ -f "${pid_file}" ]; then
    local pid
    pid="$(cat "${pid_file}")"
    if kill -0 "${pid}" 2>/dev/null; then
      echo "[start] ${name} already running (pid ${pid})"
      return 1
    fi
    echo "[start] removing stale pid file for ${name}"
    rm -f "${pid_file}"
  fi
  return 0
}

toml_section_port() {
  awk -v want="$2" '
    /^\[/ { section = ($0 == "[" want "]"); next }
    section && $1 == "port" { gsub(/[^0-9]/, "", $NF); print $NF; exit }
  ' "$1" 2>/dev/null || true
}

toml_toplevel_port() {
  awk '
    /^\[/ { exit }
    $1 == "port" { gsub(/[^0-9]/, "", $NF); print $NF; exit }
  ' "$1" 2>/dev/null || true
}

wait_for_port() {
  local name="$1" pid="$2" port="$3" log_file="$4"
  echo "[start] waiting for ${name} on port ${port}"
  local deadline=$((SECONDS + 120))
  while [ "${SECONDS}" -lt "${deadline}" ]; do
    if (echo > /dev/tcp/127.0.0.1/"${port}") 2>/dev/null; then
      echo "[start] ${name} started (pid ${pid})"
      echo "[start] log: ${log_file}"
      return 0
    fi
    if ! kill -0 "${pid}" 2>/dev/null && ! sudo -n kill -0 "${pid}" 2>/dev/null; then
      echo "[start] ${name} exited during startup, see ${log_file}" >&2
      return 1
    fi
    sleep 1
  done
  echo "[start] ${name} did not open port ${port} in time, see ${log_file}" >&2
  return 1
}

check_stale_pid "${APP}" "${PID_FILE}" || exit 0
if [ "${SKIP_GATEWAY}" != "1" ]; then
  check_stale_pid "${GATEWAY}" "${GW_PID_FILE}" || exit 0
fi

mkdir -p bin run "${LOG_DIR}"

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  echo "[start] building ${APP}"
  "${GO}" build -o "${BIN}" ./cmd/belfast
  if [ "${SKIP_GATEWAY}" != "1" ]; then
    echo "[start] building ${GATEWAY}"
    "${GO}" build -o "${GW_BIN}" ./cmd/gateway
  fi
else
  echo "[start] SKIP_BUILD=1, using existing binaries"
fi

if [ ! -x "${BIN}" ]; then
  echo "[start] binary not found: ${BIN}" >&2
  exit 1
fi
if [ "${SKIP_GATEWAY}" != "1" ] && [ ! -x "${GW_BIN}" ]; then
  echo "[start] binary not found: ${GW_BIN}" >&2
  exit 1
fi

echo "[start] launching ${APP}"
nohup "${BIN}" --config "${CONFIG}" >> "${LOG_FILE}" 2>&1 &
pid=$!
echo "${pid}" > "${PID_FILE}"

wait_port="$(toml_section_port "${CONFIG}" api)"
if [ -z "${wait_port}" ]; then
  wait_port="$(toml_section_port "${CONFIG}" belfast)"
fi

if [ -n "${wait_port}" ]; then
  wait_for_port "${APP}" "${pid}" "${wait_port}" "${LOG_FILE}"
else
  echo "[start] ${APP} launched (pid ${pid})"
  echo "[start] log: ${LOG_FILE}"
fi

if [ "${SKIP_GATEWAY}" = "1" ]; then
  echo "[start] SKIP_GATEWAY=1, gateway not started"
  exit 0
fi

gw_port="$(toml_toplevel_port "${GW_CONFIG}")"

launcher=()
if [ -n "${gw_port}" ] && [ "${gw_port}" -lt 1024 ] && [ "$(id -u)" -ne 0 ]; then
  launcher=(sudo -n)
fi

echo "[start] launching ${GATEWAY}"
nohup "${launcher[@]}" "${GW_BIN}" --config "${GW_CONFIG}" >> "${GW_LOG_FILE}" 2>&1 &
gw_pid=$!
echo "${gw_pid}" > "${GW_PID_FILE}"

if [ -n "${gw_port}" ]; then
  wait_for_port "${GATEWAY}" "${gw_pid}" "${gw_port}" "${GW_LOG_FILE}"
else
  echo "[start] ${GATEWAY} launched (pid ${gw_pid})"
  echo "[start] log: ${GW_LOG_FILE}"
fi

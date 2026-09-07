#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP="belfast"
PID_FILE="run/${APP}.pid"

if [ ! -f "${PID_FILE}" ]; then
  echo "[stop] ${APP} not running (no pid file)"
  exit 0
fi

pid="$(cat "${PID_FILE}")"

if ! kill -0 "${pid}" 2>/dev/null; then
  echo "[stop] ${APP} not running (stale pid file)"
  rm -f "${PID_FILE}"
  exit 0
fi

echo "[stop] stopping ${APP} (pid ${pid})"
kill -INT "${pid}" 2>/dev/null || true

for _ in $(seq 1 40); do
  if ! kill -0 "${pid}" 2>/dev/null; then
    rm -f "${PID_FILE}"
    echo "[stop] ${APP} stopped"
    exit 0
  fi
  sleep 0.5
done

echo "[stop] ${APP} did not exit gracefully, forcing kill" >&2
kill -9 "${pid}" 2>/dev/null || true
rm -f "${PID_FILE}"
echo "[stop] ${APP} killed"

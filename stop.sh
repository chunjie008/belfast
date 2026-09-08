#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

proc_alive() {
  kill -0 "$1" 2>/dev/null || sudo -n kill -0 "$1" 2>/dev/null
}

signal_proc() {
  kill "$1" "$2" 2>/dev/null || sudo -n kill "$1" "$2" 2>/dev/null || true
}

wait_dead() {
  local pid="$1" tries="$2"
  for _ in $(seq 1 "${tries}"); do
    if ! proc_alive "${pid}"; then
      return 0
    fi
    sleep 0.5
  done
  return 1
}

stop_app() {
  local name="$1" pid_file="run/$1.pid"

  if [ ! -f "${pid_file}" ]; then
    echo "[stop] ${name} not running (no pid file)"
    return 0
  fi

  local pid
  pid="$(cat "${pid_file}")"

  if ! proc_alive "${pid}"; then
    echo "[stop] ${name} not running (stale pid file)"
    rm -f "${pid_file}"
    return 0
  fi

  echo "[stop] stopping ${name} (pid ${pid})"
  signal_proc -INT "${pid}"
  if wait_dead "${pid}" 40; then
    rm -f "${pid_file}"
    echo "[stop] ${name} stopped"
    return 0
  fi

  echo "[stop] ${name} ignored SIGINT, sending SIGTERM" >&2
  signal_proc -TERM "${pid}"
  if wait_dead "${pid}" 40; then
    rm -f "${pid_file}"
    echo "[stop] ${name} stopped"
    return 0
  fi

  echo "[stop] ${name} did not exit gracefully, forcing kill" >&2
  signal_proc -9 "${pid}"
  rm -f "${pid_file}"
  echo "[stop] ${name} killed"
}

stop_app gateway
stop_app belfast

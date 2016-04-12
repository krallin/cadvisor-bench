#!/bin/bash
set -o errexit
set -o nounset

# Expect variables:
# CADVISOR
# CG_ROOT
# CG_NAME
# OUT_BASE

# Some handy variables
cg_descriptor="cpuacct,memory:${CG_NAME}"
cpu_usage_file="${CG_ROOT}/cpuacct/${CG_NAME}/cpuacct.usage"
mem_usage_file="${CG_ROOT}/memory/${CG_NAME}/memory.usage_in_bytes"

# Delete the cgroup and recreate it
sudo cgdelete -g "$cg_descriptor" 2>&1 >/dev/null || true
sudo cgcreate -g "$cg_descriptor"

# Confirm that the cgroups were created
for cgroup in cpuacct memory; do
  tasks_file="${CG_ROOT}/${cgroup}/${CG_NAME}/tasks"
  if [[ ! -f "$tasks_file" ]]; then
    echo "Cgroup does not exist: ${cgroup}:${CG_NAME} - aborting."
    exit 1
  fi
  if [[ "$(< "$tasks_file")" != "" ]]; then
    echo "Some tasks found in ${cgroup}:${CG_NAME} - aborting."
    exit 1
  fi
done

# Now, check that the counters are all at zero
for counter in "$cpu_usage_file" "$mem_usage_file"; do
  if [[ "$(< "$counter")" != "0" ]]; then
    echo "Usage counter in ${counter} is not at 0 - aborting."
    exit 1
  fi
done

# Create our run dir in the results path
RUN_DIR="${OUT_BASE}.run"
mkdir -p "$RUN_DIR"

# Capture the cAdvisor version for reporting
cadvisor_version="$("$CADVISOR" --version)"

# Start cAdvisor, in the cgroups. Capture a PID to kill it later.
# TODO: Remove the panic timeout if I ever upstream this
sudo cgexec -g "$cg_descriptor" "$(which $CADVISOR)" \
  --enable_load_reader \
  --docker_only \
  --storage_driver=stdout \
  --panic_timeout=10m \
  --listen_path "${RUN_DIR}/sock" \
  --log_dir "${RUN_DIR}" \
  2>&1 > "${RUN_DIR}/out" &
CADVISOR_PID="$!"  # Technially sudo's, but that's fine

# Kill cAdvisor when this shell script exits
trap 'echo "Exiting cAdvisor ${CADVISOR_PID}"; sudo kill -TERM "$CADVISOR_PID"' EXIT

# Start reporting
results="${OUT_BASE}.csv"
echo "Time,Version,Alive,Memory in bytes,CPU in ns" > "$results"
while true; do
  alive="1"
  sudo kill -0 "$CADVISOR_PID" || {
    alive="0"
  }
  echo "\"$(date -Ins -u)\",\"$cadvisor_version\",\"$alive\",\"$(< "$mem_usage_file")\",\"$(< "$cpu_usage_file")\"" >> "$results"
  sleep 1
done

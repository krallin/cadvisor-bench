#!/bin/bash
set -o errexit nounset

CG_ROOT="/sys/fs/cgroup"

OUT_FILE="perf.out"
TEST_CG_NAME="test-cadvisor"

cpu_usage_file="${CG_ROOT}/cpuacct/${TEST_CG_NAME}/cpuacct.usage"
mem_usage_file="${CG_ROOT}/memory/${TEST_CG_NAME}/memory.usage_in_bytes"


if [[ "$(docker ps -q)" != "" ]]; then
  echo "Some Docker containers are already running - aborting."
  exit 1
fi

for cgroup in cpuacct memory; do
  tasks_file="${CG_ROOT}/${cgroup}/${TEST_CG_NAME}/tasks"
  if [[ ! -f "$tasks_file" ]]; then
    echo "Cgroup does not exist: ${cgroup}:${TEST_CG_NAME} - aborting."
    exit 1
  fi
  if [[ "$(< "$tasks_file")" != "" ]]; then
    echo "Some tasks found in ${cgroup}:${TEST_CG_NAME} - aborting."
    exit 1
  fi
done

# Pull image beforehand
echo "Pulling test image"
# docker pull alpine

# Reset CPU counters
echo "Resetting CPU counters"
echo 0 > "$cpu_usage_file"

if [[ "$(< "$cpu_usage_file")" != "0" ]]; then
  echo "Failed to clear CPU counters-  aborting."
  exit 1
fi

echo "Clearing Memory counters"
echo 0 > "${CG_ROOT}/memory/${TEST_CG_NAME}/memory.force_empty"

if [[ "$(< "$mem_usage_file")" != "0" ]]; then
  echo "Failed to clear memory counters - aborting."
  exit 1
fi

echo "Starting test"
CADVISOR_VERSION="$(cadvisor --version)"
sudo cgexec -g "cpuacct,memory:${TEST_CG_NAME}" "$(which cadvisor)" --enable_load_reader --docker_only --logtostderr &
CADVISOR_PID="$?"  # Technially sudo's, but that's fine

(
  # Start some containers that will start and die throughout the test
  for i in $(seq 0 199); do
    docker run -d alpine sleep "$((200 - i))"
    # sleep 1
  done

  # Now, start some more containers that'll persist for a while longer
  for i in $(seq 0 199); do
    docker run -d alpine sleep 200
    # sleep 1
  done

  echo "Done dispatching containers"
) &

echo "Time,Version,Memory in bytes,CPU in ns" > "$OUT_FILE"
for _ in $(seq 0 599); do
  echo "\"$(date -Ins -u)\",\"$CADVISOR_VERSION\",\"$(< "$mem_usage_file")\",\"$(< "$cpu_usage_file")\"" >> "$OUT_FILE"
  sleep 1
done

sudo kill -TERM "$CADVISOR_PID"

echo "Done running test!"

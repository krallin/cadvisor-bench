#!/bin/bash
set -o errexit
set -o nounset

TEST_NAME="cadvisor-$(date +%s)"
RESULTS_PATH="perf-results/${TEST_NAME}.perf"

if [[ -n "$(docker ps -q)" ]]; then
  echo "Some containers are live - aborting."
  exit 1
fi

# Start the cAdvisors
export CG_ROOT="/sys/fs/cgroup"

WORKER_PIDS=()
for v in control candidate; do
  CADVISOR="cadvisor.${v}" CG_NAME="cadvisor-test-${v}" OUT_BASE="${RESULTS_PATH}/${v}" ./run-cadvisor.sh &
  WORKER_PIDS+=("$!")
done

trap 'echo "Exiting workers ${WORKER_PIDS[@]}"; kill -TERM "${WORKER_PIDS[@]}"' EXIT


GRACE_PERIOD=5
for i in $(seq 0 "$GRACE_PERIOD"); do
  if [[ -f "${RESULTS_PATH}/control.csv" ]] && [[ -f "${RESULTS_PATH}/candidate.csv" ]]; then
    echo "Test files were created - starting!"
    break
  fi
  sleep 1
done

if [[ "$i" -ge "$GRACE_PERIOD" ]]; then
  echo "cAdvisors failed to start - aborting."
  exit 1
fi

# Pull image beforehand
echo "Pulling test image"
docker pull debian

# Log the number of containers running
OUT_BASE="${RESULTS_PATH}/containers" ./log-containers.sh &
WORKER_PIDS+=("$!")

startTs="$(date +%s)"

# First, start some containers whose workload will vary throughout the test (they'll be active ~10% of the time)
# We give those a small amount of CPU time to avoid starving the system for CPU (we don't care that those tasks actually
# run, we just want their stats to update)
echo "Starting yes workers"
for i in $(seq 0 100); do
  # We allow the process to run for 1% of a second, every second (per CPU).
  docker run --cpu-quota=10000 --cpu-period=1000000 -d debian bash -c 'while true; do sleep $((RANDOM % 100 + 1)); echo Go; timeout -sKILL $((RANDOM % 10 + 1)) yes > /dev/null; done'
done

# Start some containers that will start and die throughout the test
echo "Starting short sleepers"
for i in $(seq 0 199); do
  docker run -d debian sleep "$((200 - i))"
done

# Now, start some more containers that'll persist for a while longer
echo "Starting long sleepers"
for i in $(seq 0 199); do
  docker run -d debian sleep 600
done

echo "Done dispatching containers"

doneTs="$(date +%s)"

# We are targetting 10 minutes of test (60s), so wait until that
duration=600
sleepFor="$(($duration - ($doneTs - $startTs)))"
if [[ "$sleepFor" -gt 0 ]]; then
  echo "Sleeping for $sleepFor seconds ot complete $duration test run"
  sleep "$sleepFor"
fi


# And wait for 10 more minutes
sleep 600

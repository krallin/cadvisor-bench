#!/bin/bash
set -o errexit
set -o nounset

# Expect variables:
# OUT_BASE

results="${OUT_BASE}.csv"
echo "Time,Containers" > "$results"
while true; do
  container_count=$(docker ps -q | wc -l)
  echo "\"$(date -Ins -u)\",\"$container_count\"" >> "$results"
  sleep 1
done

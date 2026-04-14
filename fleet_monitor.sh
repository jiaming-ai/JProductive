#!/bin/bash
# Compact live resource monitor for a remote server
# Usage: fleet_monitor.sh <server>
SERVER="${1:?Usage: fleet_monitor.sh <server>}"

SCRIPT=$(cat <<'ENDSCRIPT'
CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "?")
while true; do
  clear
  printf "\033[1m=== %s ===\033[0m\n" "$(hostname)"
  if command -v nvidia-smi >/dev/null 2>&1; then
    nvidia-smi --query-gpu=index,utilization.gpu,memory.used,memory.total \
      --format=csv,noheader,nounits 2>/dev/null | \
      awk -F', ' '{printf "GPU%-2s %3d%% | VRAM %5.1fG/%5.1fG\n", $1, $2, $3/1024, $4/1024}'
  fi
  awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{u=t-a; printf "RAM  %5.1fG/%5.1fG (%2.0f%%)\n", u/1048576, t/1048576, u*100/t}' /proc/meminfo
  S1=$(head -1 /proc/stat); sleep 1; S2=$(head -1 /proc/stat)
  printf '%s\n%s\n' "$S1" "$S2" | awk -v c="$CORES" '
    NR==1{for(i=2;i<=NF;i++)t1+=$i;d1=$5}
    NR==2{for(i=2;i<=NF;i++)t2+=$i;d2=$5}
    END{dt=t2-t1;di=d2-d1;if(dt>0)printf "CPU  %5.1f%% (%d cores)\n",(dt-di)*100/dt,c}'
done
ENDSCRIPT
)

exec ssh -o ConnectTimeout=5 -t "$SERVER" "bash -c $(printf '%q' "$SCRIPT")"

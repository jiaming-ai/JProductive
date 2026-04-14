#!/bin/bash
# Compact flicker-free live resource monitor for a remote server
# Usage: fleet_monitor.sh <server>
SERVER="${1:?Usage: fleet_monitor.sh <server>}"

SCRIPT=$(cat <<'ENDSCRIPT'
CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "?")
HOST=$(hostname)
HAS_NVIDIA=0
command -v nvidia-smi >/dev/null 2>&1 && HAS_NVIDIA=1

# Initial clear + hide cursor
printf '\033[2J\033[H\033[?25l'
trap 'printf "\033[?25h"' EXIT INT TERM

while true; do
    # Sample CPU (the 1s sleep here also paces the frame rate)
    S1=$(head -1 /proc/stat)
    sleep 1
    S2=$(head -1 /proc/stat)

    CPU=$(printf '%s\n%s\n' "$S1" "$S2" | awk '
        NR==1{for(i=2;i<=NF;i++)t1+=$i; d1=$5}
        NR==2{for(i=2;i<=NF;i++)t2+=$i; d2=$5}
        END{dt=t2-t1; di=d2-d1; if(dt>0) printf "%.1f", (dt-di)*100/dt; else printf "0.0"}')

    RAM=$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{u=t-a; printf "%.1f/%.1fG %2.0f%%", u/1048576, t/1048576, u*100/t}' /proc/meminfo)

    GPU_DATA=""
    if [ "$HAS_NVIDIA" = "1" ]; then
        GPU_DATA=$(nvidia-smi --query-gpu=index,utilization.gpu,memory.used,memory.total \
            --format=csv,noheader,nounits 2>/dev/null | \
            awk -F', ' '{printf "%3s|%3d|%4.1f/%4.1f\033[K\n", $1, $2, $3/1024, $4/1024}')
    fi

    # Emit whole frame from cursor-home; \033[K clears rest of each line, \033[J clears below
    {
        printf '\033[H'
        printf '\033[1m%s\033[0m\033[K\n' "$HOST"
        printf 'GPU|UTI|VRAM(G)\033[K\n'
        [ -n "$GPU_DATA" ] && printf '%s' "$GPU_DATA"
        printf 'RAM %s\033[K\n' "$RAM"
        printf 'CPU %s%% %sc\033[K\n' "$CPU" "$CORES"
        printf '\033[J'
    }
done
ENDSCRIPT
)

exec ssh -o ConnectTimeout=5 -t "$SERVER" "bash -c $(printf '%q' "$SCRIPT")"

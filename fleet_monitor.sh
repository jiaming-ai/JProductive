#!/bin/bash
# Compact flicker-free live resource monitor for a remote server
# Usage: fleet_monitor.sh <server>
#
# Sidebar target width: 18 cols. Worst-case lines:
#   RAM line:  "RAM 9999/9999 99%" = 17
#   CPU line:  "CPU 100% 128/128c" = 17
#   R/W line:  "R 1023G 100%"      = 12
#   Disk line: "mntnm 9999/99999"  = 17 (basename 5 chars, sizes in GB, no unit)
#   GPU line:  " 0|100|141/141"    = 14
SERVER="${1:?Usage: fleet_monitor.sh <server>}"

SCRIPT=$(cat <<'ENDSCRIPT'
CORES=$(nproc 2>/dev/null || grep -c ^processor /proc/cpuinfo 2>/dev/null || echo "?")
HOST=$(hostname)
HAS_NVIDIA=0
command -v nvidia-smi >/dev/null 2>&1 && HAS_NVIDIA=1

printf '\033[2J\033[H\033[?25l'
trap 'printf "\033[?25h"' EXIT INT TERM

while true; do
    # --- Sample two readings 1 second apart ---
    CPU1=$(grep '^cpu' /proc/stat)
    DISK1=$(cat /proc/diskstats 2>/dev/null)
    sleep 1
    CPU2=$(grep '^cpu' /proc/stat)
    DISK2=$(cat /proc/diskstats 2>/dev/null)

    # --- CPU: overall util + fully-utilized core count (>=90% busy) ---
    CPU_STATS=$(printf '%s\n---\n%s\n' "$CPU1" "$CPU2" | awk '
        /^---$/ { phase=2; next }
        phase!=2 {
            if ($1=="cpu") { t1=0; for(i=2;i<=NF;i++) t1+=$i; d1=$5 }
            else if ($1 ~ /^cpu[0-9]+$/) {
                c=substr($1,4)+0
                ct1[c]=0; for(i=2;i<=NF;i++) ct1[c]+=$i
                cd1[c]=$5
            }
        }
        phase==2 {
            if ($1=="cpu") { t2=0; for(i=2;i<=NF;i++) t2+=$i; d2=$5 }
            else if ($1 ~ /^cpu[0-9]+$/) {
                c=substr($1,4)+0
                ct2[c]=0; for(i=2;i<=NF;i++) ct2[c]+=$i
                cd2[c]=$5
            }
        }
        END {
            dt=t2-t1; di=d2-d1
            cpu = dt>0 ? (dt-di)*100/dt : 0
            full=0
            for (c in ct2) {
                cdt=ct2[c]-ct1[c]; cdi=cd2[c]-cd1[c]
                if (cdt>0 && (cdt-cdi)*100/cdt >= 90) full++
            }
            printf "%.0f %d", cpu, full
        }')
    read -r CPU_PCT FULL_CORES <<< "$CPU_STATS"

    # --- IO: aggregate read/write throughput + busy-% across real disks ---
    IO_STATS=$(printf '%s\n---\n%s\n' "$DISK1" "$DISK2" | awk '
        function fmt(b) {
            if (b < 1024)             return sprintf("%dB", b)
            if (b < 1048576)          return sprintf("%dK", b/1024)
            if (b < 1073741824)       return sprintf("%dM", b/1048576)
            if (b < 1099511627776)    return sprintf("%dG", b/1073741824)
            return                           sprintf("%.1fT", b/1099511627776)
        }
        /^---$/ { phase=2; next }
        NF<13 { next }
        $3 !~ /^(sd[a-z]+|nvme[0-9]+n[0-9]+|vd[a-z]+|xvd[a-z]+|mmcblk[0-9]+)$/ { next }
        phase!=2 { r1[$3]=$6; w1[$3]=$10; mr1[$3]=$7; mw1[$3]=$11 }
        phase==2 { r2[$3]=$6; w2[$3]=$10; mr2[$3]=$7; mw2[$3]=$11 }
        END {
            rs=0; ws=0; mrm=0; mwm=0
            for (k in r2) {
                rs += r2[k]-r1[k]
                ws += w2[k]-w1[k]
                rd = mr2[k]-mr1[k]; wd = mw2[k]-mw1[k]
                if (rd > mrm) mrm = rd
                if (wd > mwm) mwm = wd
            }
            # sectors -> bytes/sec (1s window, 512 bytes/sector)
            rb = rs * 512
            wb = ws * 512
            # busy-% per direction (ms / 10), capped
            rp = mrm/10; if (rp>100) rp=100
            wp = mwm/10; if (wp>100) wp=100
            printf "%s %s %.0f %.0f", fmt(rb), fmt(wb), rp, wp
        }')
    read -r R_RATE W_RATE R_PCT W_PCT <<< "$IO_STATS"
    [ -z "${R_RATE:-}" ] && { R_RATE=0B; W_RATE=0B; R_PCT=0; W_PCT=0; }

    # --- Disk space: per-mount, total >= 100GB, sizes in GB (no unit) ---
    DISK_LINES=$(df -P -B1G 2>/dev/null | awk '
        NR==1 { next }
        $2+0 < 100 { next }
        {
            m=$6
            if (m == "/") name="/"
            else {
                n=split(m, a, "/")
                name=a[n]
                if (length(name) > 5) name=substr(name,1,5)
            }
            printf "%s %d/%d\033[K\n", name, $3+0, $2+0
        }')

    # --- RAM ---
    RAM=$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{u=t-a; printf "%.0f/%.0f %2.0f", u/1048576, t/1048576, u*100/t}' /proc/meminfo)

    # --- GPU ---
    GPU_DATA=""
    if [ "$HAS_NVIDIA" = "1" ]; then
        GPU_DATA=$(nvidia-smi --query-gpu=index,utilization.gpu,memory.used,memory.total \
            --format=csv,noheader,nounits 2>/dev/null | \
            awk -F', ' '{printf "%2s|%3d|%3d/%3d\033[K\n", $1, $2, $3/1024, $4/1024}')
    fi

    # --- Render frame ---
    SEP='──────────────────'
    {
        printf '\033[H'
        printf '\033[1;35m🐱 JPro Mon 🐱\033[0m\033[K\n'
        printf '\033[1m%s\033[0m\033[K\n' "$HOST"
        printf '%s\033[K\n' "$SEP"
        printf 'GPU|UTI|VRAM\033[K\n'
        [ -n "$GPU_DATA" ] && printf '%s\n' "$GPU_DATA"
        printf '%s\033[K\n' "$SEP"
        printf 'RAM %s%%\033[K\n' "$RAM"
        printf 'CPU %s%% %s/%sc\033[K\n' "$CPU_PCT" "$FULL_CORES" "$CORES"
        printf '%s\033[K\n' "$SEP"
        printf 'R %s %s%%\033[K\n' "$R_RATE" "$R_PCT"
        printf 'W %s %s%%\033[K\n' "$W_RATE" "$W_PCT"
        [ -n "$DISK_LINES" ] && printf '%s\n' "$DISK_LINES"
        printf '\033[J'
    }
done
ENDSCRIPT
)

exec ssh -o ConnectTimeout=5 -t "$SERVER" "bash -c $(printf '%q' "$SCRIPT")"

#!/bin/bash
# ct_split.sh - smart split for ct server windows.
# In a server window: remotely splits the pane in the remote tmux session
# (appears live in the attached SSH pane). Otherwise: normal local split.
# Usage: ct_split.sh <h|v> <window_name> [pane_current_path]
DIR="${1:-h}"
WIN="${2:-}"
CWD="${3:-$HOME}"
SERVERS_FILE="$HOME/.auto_fleet/current_servers"

SPLIT_FLAG="-$DIR"

# Check if current window belongs to a known server (server names may contain dashes,
# so match against the saved list instead of parsing by separator).
if [ -f "$SERVERS_FILE" ] && [[ "$WIN" == *-* ]]; then
    while IFS= read -r srv; do
        [ -z "$srv" ] && continue
        if [[ "$WIN" == "$srv-"* ]]; then
            SESSION="${WIN#$srv-}"
            # Remote split - tmux targets session's currently active pane automatically.
            # New pane appears live in the attached SSH pane; no local split occurs.
            ssh -n -o ConnectTimeout=5 "$srv" \
                "tmux split-window $SPLIT_FLAG -t '$SESSION'" \
                </dev/null >/dev/null 2>&1
            exit 0
        fi
    done < "$SERVERS_FILE"
fi

# Fall back to local split
tmux split-window "$SPLIT_FLAG" -c "$CWD"

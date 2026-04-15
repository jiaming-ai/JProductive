#!/bin/bash

LOCAL_SESSION="auto_fleet"
MONITOR_SCRIPT="$HOME/.auto_fleet/fleet_monitor.sh"

# Parse --new flag
CREATE_NEW=0
SERVERS=()
for arg in "$@"; do
    case "$arg" in
        -n|--new) CREATE_NEW=1 ;;
        *)     SERVERS+=("$arg") ;;
    esac
done

# 1. Determine the list of servers (from arguments OR a file)
if [ ${#SERVERS[@]} -eq 0 ]; then
    if [ -f "servers.txt" ]; then
        mapfile -t SERVERS < <(grep -v '^[[:space:]]*$' servers.txt)
    fi
fi

if [ ${#SERVERS[@]} -eq 0 ]; then
    echo "Usage: $0 [--new] <server1> [server2] ..."
    echo "Or create a 'servers.txt' file in the same directory."
    exit 1
fi

# Always re-source local tmux config so binding updates from `git pull` take
# effect, even when we just reattach to an existing session.
LOCAL_TMUX_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
[ -f "$LOCAL_TMUX_CONF" ] || LOCAL_TMUX_CONF="$HOME/.tmux.conf"
tmux source-file "$LOCAL_TMUX_CONF" 2>/dev/null || true

# 2. Check if local session already exists
if tmux has-session -t "$LOCAL_SESSION" 2>/dev/null; then
    # Extract server names from existing window names (format: server-session)
    EXISTING_SERVERS=$(tmux list-windows -t "$LOCAL_SESSION" -F '#{window_name}' | sed 's/-[^-]*$//' | sort -u)
    REQUESTED_SERVERS=$(printf '%s\n' "${SERVERS[@]}" | sort -u)

    if [ "$EXISTING_SERVERS" = "$REQUESTED_SERVERS" ]; then
        echo "Local session '$LOCAL_SESSION' already exists. Attaching..."
        tmux attach -t "$LOCAL_SESSION"
        exit 0
    else
        echo "Server list changed. Restarting session..."
        tmux kill-session -t "$LOCAL_SESSION"
    fi
fi

# Push the JProductive tmux config + auto_fleet scripts to each server so
# nested-tmux features (mouse pass-through, bindings) work consistently.
# Light-weight: just git pull + symlink/cp + source-file.  No heavy tool
# installs (nvm/micromamba/etc) -- those are the user's call via the full
# install script.  Runs in parallel across servers.  Logs to /tmp for
# debugging when something goes wrong.
remote_sync_oneliner='
set -e
LOG=/tmp/ct_remote_sync.log
exec >>"$LOG" 2>&1
echo "=== $(date -Is) sync start on $(hostname) ==="
mkdir -p ~/.JProductive
if [ -d ~/.JProductive/.git ]; then
    git -C ~/.JProductive pull --ff-only -q || echo "git pull failed"
else
    rm -rf ~/.JProductive
    git clone --depth 1 https://github.com/jiaming-ai/JProductive.git ~/.JProductive || echo "git clone failed"
fi
# Tmux reads ~/.tmux.conf first; only if absent does it fall back to the XDG
# path.  To avoid ambiguity we deploy to ~/.tmux.conf (the dominant path) and
# actively remove any XDG tmux.conf so there is ONE authoritative file.
rm -f "$HOME/.tmux.conf" "$HOME/.tmux.conf.local"
rm -f "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf" \
      "${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf.local"
ln -sfn ~/.JProductive/.tmux.conf       "$HOME/.tmux.conf"
cp   -f ~/.JProductive/.tmux.conf.local "$HOME/.tmux.conf.local"
# auto_fleet helper scripts
mkdir -p ~/.auto_fleet
for f in auto_fleet.sh fleet_monitor.sh ct_split.sh ct; do
    if [ -f ~/.JProductive/"$f" ]; then
        cp -f ~/.JProductive/"$f" ~/.auto_fleet/"$f"
        chmod +x ~/.auto_fleet/"$f"
    fi
done
# Reload config in running tmux server so the change applies NOW
tmux source-file "$HOME/.tmux.conf" 2>/dev/null \
    && echo "config reloaded in tmux server (mouse=$(tmux show-options -gv mouse 2>/dev/null))" \
    || echo "no running tmux server (will apply on next start)"
echo "=== sync done ==="
'
if [ "${CT_DO_REMOTE_SYNC:-0}" = "1" ]; then
    echo "Syncing JProductive config to ${#SERVERS[@]} server(s)..."
    SYNC_PIDS=()
    for server in "${SERVERS[@]}"; do
        (
            if timeout 30 ssh -o ConnectTimeout=5 -o BatchMode=yes "$server" \
                "$remote_sync_oneliner" </dev/null >/dev/null 2>&1; then
                echo "  [+] $server"
            else
                echo "  [!] $server (failed; check /tmp/ct_remote_sync.log on host)"
            fi
        ) &
        SYNC_PIDS+=($!)
    done
    wait "${SYNC_PIDS[@]}" 2>/dev/null
    echo "Sync complete."
fi

echo "Scanning servers for active tmux sessions..."
# Create session sized to the current terminal so -l 20 actually means 20 columns
# (tmux preserves pane *proportions* on resize, so sizes set in a small default
# session get scaled up when the client attaches on a wider terminal)
CLIENT_COLS=$(tput cols 2>/dev/null || echo 200)
CLIENT_LINES=$(tput lines 2>/dev/null || echo 50)
tmux new-session -d -s "$LOCAL_SESSION" -n "scanning..." -x "$CLIENT_COLS" -y "$CLIENT_LINES"
FIRST_WINDOW="$(tmux list-windows -t "$LOCAL_SESSION" -F '#{window_index}' | head -1)"

FIRST_WINDOW_CREATED=0
# Sidebar width sized to the widest line the monitor can emit:
#   RAM line: "RAM 9999/9999 99%" = 17
#   CPU line: "CPU 100% 128/128c" = 17
SIDEBAR_WIDTH=18
CONNECTED_SERVERS=()
CURRENT_SERVERS_FILE="$HOME/.auto_fleet/current_servers"

# Helper to create a local window for a remote session (with monitor sidebar)
create_window() {
    local server="$1" session="$2"
    local WINDOW_NAME="${server}-${session}"
    local SSH_CMD="ssh -t $server 'tmux attach -t $session'"

    echo "  -> Found session: $session. Creating tab: $WINDOW_NAME"

    if [ $FIRST_WINDOW_CREATED -eq 0 ]; then
        tmux rename-window -t "${LOCAL_SESSION}:${FIRST_WINDOW}" "$WINDOW_NAME"
        tmux send-keys -t "${LOCAL_SESSION}:${FIRST_WINDOW}" "$SSH_CMD" C-m
        FIRST_WINDOW_CREATED=1
    else
        tmux new-window -t "$LOCAL_SESSION" -n "$WINDOW_NAME" "$SSH_CMD"
    fi

    # Add monitor sidebar on the right, force absolute width, focus back on SSH pane
    tmux split-window -h -l "$SIDEBAR_WIDTH" -t "${LOCAL_SESSION}:${WINDOW_NAME}" \
        "bash '$MONITOR_SCRIPT' '$server'"
    tmux resize-pane -x "$SIDEBAR_WIDTH" -t "${LOCAL_SESSION}:${WINDOW_NAME}"
    tmux select-pane -L -t "${LOCAL_SESSION}:${WINDOW_NAME}"
}

# 3. Iterate through servers and query tmux
for server in "${SERVERS[@]}"; do
    echo "Checking $server..."

    # Run 'tmux ls' remotely.
    # -o ConnectTimeout=5 prevents hanging if a server is offline
    # -F '#S' formats the output to return ONLY the session names
    SESSIONS=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$server" "tmux ls -F '#S'" 2>/dev/null)

    if [ -z "$SESSIONS" ]; then
        if [ "$CREATE_NEW" -eq 1 ]; then
            # Verify server is reachable before creating a session
            if ssh -o ConnectTimeout=5 -o BatchMode=yes "$server" "true" 2>/dev/null; then
                echo "  -> No sessions found. Creating new session on $server..."
                ssh -o ConnectTimeout=5 -o BatchMode=yes "$server" "tmux new-session -d -s main" 2>/dev/null
                create_window "$server" "main"
                CONNECTED_SERVERS+=("$server")
            else
                echo "  -> Server unreachable."
            fi
        else
            echo "  -> No active sessions found (or server unreachable)."
        fi
        continue
    fi

    CONNECTED_SERVERS+=("$server")

    # 4. Create a local tab for EVERY remote session found
    for session in $SESSIONS; do
        create_window "$server" "$session"
    done
done

# Persist list of connected servers so ct_split.sh can recognize server windows
if [ ${#CONNECTED_SERVERS[@]} -gt 0 ]; then
    printf '%s\n' "${CONNECTED_SERVERS[@]}" | sort -u > "$CURRENT_SERVERS_FILE"
fi

# 5. Final check
if [ $FIRST_WINDOW_CREATED -eq 0 ]; then
    echo "No tmux sessions found on any provided servers."
    tmux kill-session -t "$LOCAL_SESSION"
    exit 1
else
    echo "Done! Attaching to your dynamic fleet..."
    tmux attach -t "$LOCAL_SESSION"
fi

#!/bin/bash

LOCAL_SESSION="auto_fleet"

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

echo "Scanning servers for active tmux sessions..."
# Start a detached local session with a placeholder window
tmux new-session -d -s "$LOCAL_SESSION" -n "scanning..."
FIRST_WINDOW="$(tmux list-windows -t "$LOCAL_SESSION" -F '#{window_index}' | head -1)"

FIRST_WINDOW_CREATED=0

# Helper to create a local window for a remote session
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
            else
                echo "  -> Server unreachable."
            fi
        else
            echo "  -> No active sessions found (or server unreachable)."
        fi
        continue
    fi

    # 4. Create a local tab for EVERY remote session found
    for session in $SESSIONS; do
        create_window "$server" "$session"
    done
done

# 5. Final check
if [ $FIRST_WINDOW_CREATED -eq 0 ]; then
    echo "No tmux sessions found on any provided servers."
    tmux kill-session -t "$LOCAL_SESSION"
    exit 1
else
    echo "Done! Attaching to your dynamic fleet..."
    tmux attach -t "$LOCAL_SESSION"
fi

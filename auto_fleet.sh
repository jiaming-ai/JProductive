#!/bin/bash

LOCAL_SESSION="auto_fleet"

# 1. Determine the list of servers (from arguments OR a file)
if [ $# -gt 0 ]; then
    # Use arguments if provided (e.g., ./auto_fleet.sh naga majores)
    SERVERS=("$@")
elif [ -f "servers.txt" ]; then
    # Read from servers.txt if it exists (ignoring empty lines)
    mapfile -t SERVERS < <(grep -S '[^[:space:]]' servers.txt)
else
    echo "Usage: $0 <server1> [server2] ..."
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

# 3. Iterate through servers and query tmux
for server in "${SERVERS[@]}"; do
    echo "Checking $server..."
    
    # Run 'tmux ls' remotely. 
    # -o ConnectTimeout=5 prevents hanging if a server is offline
    # -F '#S' formats the output to return ONLY the session names
    SESSIONS=$(ssh -o ConnectTimeout=5 -o BatchMode=yes "$server" "tmux ls -F '#S'" 2>/dev/null)

    if [ -z "$SESSIONS" ]; then
        echo "  -> No active sessions found (or server unreachable)."
        continue
    fi

    # 4. Create a local tab for EVERY remote session found
    for session in $SESSIONS; do
        WINDOW_NAME="${server}-${session}"
        echo "  -> Found session: $session. Creating tab: $WINDOW_NAME"

        SSH_CMD="ssh -t $server 'tmux attach -t $session'"

        if [ $FIRST_WINDOW_CREATED -eq 0 ]; then
            # Rename the placeholder window and start the SSH connection
            tmux rename-window -t "${LOCAL_SESSION}:${FIRST_WINDOW}" "$WINDOW_NAME"
            tmux send-keys -t "${LOCAL_SESSION}:${FIRST_WINDOW}" "$SSH_CMD" C-m
            FIRST_WINDOW_CREATED=1
        else
            # Open a new window for subsequent sessions
            tmux new-window -t "$LOCAL_SESSION" -n "$WINDOW_NAME" "$SSH_CMD"
        fi
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
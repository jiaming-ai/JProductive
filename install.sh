#!/bin/bash
# J-pro-tools installer
# Single script to set up a productive development environment.
# Installs: tmux config, vim config, micromamba, uv, nvm, node, codex, claude code, auto_fleet (ct)
# All tools installed as user in local directories.
set -euo pipefail

REPO_URL="https://github.com/jiaming-ai/JProductive.git"
CLONE_DIR="$HOME/.JProductive"

# When piped via curl|bash, BASH_SOURCE is unset and the repo files aren't
# available locally.  Clone the repo first, then re-exec from the clone.
if [ -z "${BASH_SOURCE[0]:-}" ] || [ "${BASH_SOURCE[0]}" = "bash" ]; then
  if [ -d "$CLONE_DIR/.git" ]; then
    git -C "$CLONE_DIR" pull --ff-only -q 2>/dev/null || true
  else
    git clone "$REPO_URL" "$CLONE_DIR"
  fi
  exec bash "$CLONE_DIR/install.sh" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ${EUID:-$(id -u)} -eq 0 ]; then
  printf '!! Do not run this script as root.\n' >&2 && exit 1
fi

# --- Helpers ---

info()  { printf '[*] %s\n' "$*"; }
ok()    { printf '[+] %s\n' "$*"; }
skip()  { printf '[-] %s already installed, skipping.\n' "$*"; }

ensure_dir() { [ -d "$1" ] || mkdir -p "$1"; }

# --- 1. Tmux config ---

install_tmux_config() {
  info "Setting up tmux config..."

  if [ -d "${XDG_CONFIG_HOME:-$HOME/.config}" ]; then
    ensure_dir "${XDG_CONFIG_HOME:-$HOME/.config}/tmux"
    TMUX_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf"
  else
    TMUX_CONF="$HOME/.tmux.conf"
  fi
  TMUX_CONF_LOCAL="$TMUX_CONF.local"

  now=$(date +'%Y%m%d%H%M%S')

  # Backup existing configs
  for conf in "$TMUX_CONF" "$TMUX_CONF_LOCAL"; do
    if [ -f "$conf" ] && [ ! -L "$conf" ]; then
      info "Backing up $conf -> ${conf}.${now}"
      mv "$conf" "${conf}.${now}"
    elif [ -L "$conf" ]; then
      rm -f "$conf"
    fi
  done

  ln -sf "$SCRIPT_DIR/.tmux.conf" "$TMUX_CONF"
  cp -f "$SCRIPT_DIR/.tmux.conf.local" "$TMUX_CONF_LOCAL"

  ok "Tmux config installed (conf: $TMUX_CONF)"
}

# --- 2. Vim config ---

install_vim_config() {
  info "Setting up vim config..."

  ensure_dir "$HOME/.vim/undodir"

  if [ -f "$HOME/.vimrc" ] && ! grep -q 'J-pro-tools' "$HOME/.vimrc" 2>/dev/null; then
    now=$(date +'%Y%m%d%H%M%S')
    info "Backing up existing .vimrc -> .vimrc.${now}"
    mv "$HOME/.vimrc" "$HOME/.vimrc.${now}"
  fi

  ln -sf "$SCRIPT_DIR/vimrc" "$HOME/.vimrc"
  ok "Vim config installed (~/.vimrc -> $SCRIPT_DIR/vimrc)"
}

# --- 3. Micromamba ---

install_micromamba() {
  if command -v micromamba &>/dev/null; then
    skip "micromamba"
    return
  fi
  info "Installing micromamba..."
  "${SHELL}" <(curl -L micro.mamba.pm/install.sh) <<< $'y\n\n\n\ny\n'
  ok "micromamba installed"
}

# --- 4. uv ---

install_uv() {
  if command -v uv &>/dev/null; then
    skip "uv"
    return
  fi
  info "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  ok "uv installed"
}

# --- 5. nvm + node ---

export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

install_nvm() {
  if [ -s "$NVM_DIR/nvm.sh" ]; then
    skip "nvm"
    return
  fi
  info "Installing nvm..."
  NVM_LATEST="$(curl -fsSL -o /dev/null -w '%{redirect_url}' https://github.com/nvm-sh/nvm/releases/latest | grep -oP '[^/]+$')"
  curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_LATEST}/install.sh" | bash
  ok "nvm installed"
}

load_nvm() {
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  # nvm.sh references unset variables internally; suspend nounset while sourcing
  # shellcheck disable=SC1091
  set +u
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
  set -u
}

install_node() {
  load_nvm
  if command -v node &>/dev/null; then
    skip "node"
    return
  fi
  info "Installing latest Node.js LTS via nvm..."
  set +u
  nvm install --lts
  nvm use --lts
  nvm alias default lts/*
  set -u
  ok "node $(node -v) installed"
}

# --- 6. Codex CLI ---

install_codex() {
  load_nvm
  if command -v codex &>/dev/null; then
    skip "codex"
    return
  fi
  info "Installing codex (OpenAI Codex CLI)..."
  npm install -g @openai/codex
  ok "codex installed"
}

# --- 7. Claude Code ---

install_claude_code() {
  if command -v claude &>/dev/null; then
    skip "claude code"
    return
  fi
  info "Installing Claude Code..."
  curl -fsSL https://claude.ai/install.sh | bash
  ok "claude code installed"
}

# --- 8. Auto Fleet (ct) ---

install_auto_fleet() {
  info "Setting up auto_fleet (ct)..."

  AF_DIR="$HOME/.auto_fleet"
  ensure_dir "$AF_DIR"

  cp -f "$SCRIPT_DIR/auto_fleet.sh" "$AF_DIR/auto_fleet.sh"
  cp -f "$SCRIPT_DIR/ct" "$AF_DIR/ct"
  cp -f "$SCRIPT_DIR/fleet_monitor.sh" "$AF_DIR/fleet_monitor.sh"
  chmod +x "$AF_DIR/auto_fleet.sh" "$AF_DIR/ct" "$AF_DIR/fleet_monitor.sh"

  ok "auto_fleet installed ($AF_DIR)"
}

# --- 9. Shell aliases ---

install_aliases() {
  info "Setting up shell aliases..."

  BASHRC="$HOME/.bashrc"
  [ -f "$BASHRC" ] || touch "$BASHRC"

  declare -A aliases=(
    ["claudey"]='claude --dangerously-skip-permissions'
    ["codexy"]='codex --yolo'
    ["ct"]='$HOME/.auto_fleet/ct'
  )

  for name in "${!aliases[@]}"; do
    line="alias ${name}=\"${aliases[$name]}\""
    if ! grep -qF "$line" "$BASHRC" 2>/dev/null; then
      printf '\n# J-pro-tools alias\n%s\n' "$line" >> "$BASHRC"
      ok "Added alias: $name"
    else
      skip "alias $name"
    fi
  done
}

# --- Main ---

main() {
  printf '=== J-pro-tools Setup ===\n\n'

  install_tmux_config
  install_vim_config
  install_micromamba
  install_uv
  install_nvm
  install_node
  install_codex
  install_claude_code
  install_auto_fleet
  install_aliases

  printf '\n=== All done! ===\n'
  printf 'Restart your shell or run: source ~/.bashrc\n'
}

main "$@"

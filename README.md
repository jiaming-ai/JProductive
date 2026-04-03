# J-pro-tools

One-command setup for a productive development environment on Linux (and WSL).

A single `install.sh` script that bootstraps your terminal with a curated tmux + vim config and installs essential dev tools -- all as a regular user, no `sudo` required.

## What it installs

| Tool | Description |
|------|-------------|
| **tmux config** | Themed tmux setup based on [Oh my tmux!](https://github.com/gpakosz/.tmux) with sensible defaults, vi-mode copy, mouse support, and custom keybindings |
| **vim config** | Productivity-focused vimrc with relative line numbers, persistent undo, smart search, and split navigation |
| **[micromamba](https://mamba.readthedocs.io/)** | Fast, lightweight conda package manager |
| **[uv](https://github.com/astral-sh/uv)** | Blazing-fast Python package and project manager |
| **[nvm](https://github.com/nvm-sh/nvm) + Node.js LTS** | Node version manager with the latest LTS release |
| **[Codex CLI](https://github.com/openai/codex)** | OpenAI's terminal coding assistant |
| **[Claude Code](https://claude.ai/code)** | Anthropic's CLI for Claude |

It also adds two shell aliases:
- `claudey` -- runs Claude Code with `--dangerously-skip-permissions`
- `codexy` -- runs Codex with `--yolo`

## Quick start

```bash
curl -fsSL https://raw.githubusercontent.com/jiaming-ai/JProductive/master/install.sh | bash
```

Or clone and run manually:

```bash
git clone https://github.com/jiaming-ai/JProductive.git
cd JProductive
./install.sh
```

Then restart your shell or run `source ~/.bashrc`.

## Requirements

- Linux or WSL (macOS may work but is untested)
- `bash`, `curl`, `git`
- tmux >= 2.6 (for the tmux config)
- `TERM` set to `xterm-256color` outside of tmux

## What the installer does

1. **Tmux config** -- symlinks `.tmux.conf` and copies `.tmux.conf.local` to `~/.config/tmux/` (or `~` as fallback). Backs up any existing config first.
2. **Vim config** -- symlinks the included `vimrc` to `~/.vimrc`. Backs up any existing vimrc that wasn't created by J-pro-tools.
3. **Dev tools** -- installs micromamba, uv, nvm, Node.js, Codex CLI, and Claude Code. Skips anything already installed.
4. **Aliases** -- appends `claudey` and `codexy` aliases to `~/.bashrc` if not already present.

Every step is idempotent. Re-running the installer is safe.

## Tmux keybindings

Prefix is `C-b` (default) or `C-a` (secondary).

| Binding | Action |
|---------|--------|
| `Alt+Arrow` | Switch panes (no prefix) |
| `Shift+Arrow` | Switch windows (no prefix) |
| `Ctrl+Arrow` | Resize panes (no prefix) |
| `<prefix> \|` | Split pane horizontally |
| `<prefix> -` | Split pane vertically |
| `<prefix> /` | Search in copy mode |
| `<prefix> S` | Toggle pane sync |
| `<prefix> m` | Toggle mouse |
| `<prefix> e` | Edit local config |
| `<prefix> r` | Reload config |

Copy mode uses vi bindings (`v` to select, `y` to yank).

## Vim config highlights

- Relative line numbers with current line shown
- Persistent undo across sessions (`~/.vim/undodir`)
- Incremental, case-smart search (`/` searches ignore case unless you use uppercase)
- `Ctrl+hjkl` to move between splits
- `Alt+j/k` to move lines up and down
- `Ctrl+s` to save from normal or insert mode
- 4-space indentation, visible trailing whitespace
- No swap files or backups -- undo history is the safety net

## Customization

Edit `~/.config/tmux/tmux.conf.local` (or `~/.tmux.conf.local`) to customize tmux theming, status bar, and behavior. Never modify the main `.tmux.conf` directly.

The vim config lives at `~/.vimrc` (symlinked to this repo's `vimrc`).

## Credits

The tmux configuration is based on [Oh my tmux!](https://github.com/gpakosz/.tmux) by Gregory Pakosz, dual-licensed under the [MIT](LICENSE.MIT) and [WTFPLv2](LICENSE.WTFPLv2) licenses.

## License

[MIT](LICENSE.MIT) / [WTFPLv2](LICENSE.WTFPLv2)

# machine-setup

One script that takes a fresh macOS or Linux machine to Paulie's baseline: Homebrew/dev
tools, GitHub CLI + login, the private [dotfiles](https://github.com/pauli3j/dotfiles)
(zsh + oh-my-zsh, tmux theme, Terminal profile), the
[obsidian-vault](https://github.com/pauli3j/obsidian-vault) with Obsidian Git seeded,
Claude Code, and the Obsidian app.

```bash
curl -fsSL https://raw.githubusercontent.com/pauli3j/machine-setup/main/setup.sh | bash
```

Idempotent — safe to re-run any time; an already-configured machine is a fast no-op.
Interactive at most twice: the sudo password and the GitHub browser login.

## What it does

| Step | macOS | Linux (apt / dnf) |
|---|---|---|
| Dev tools | Homebrew (installs Xcode CLT itself) | git, curl, build tools via the package manager |
| Base packages | via the dotfiles `Brewfile` | zsh, tmux, jq, cowsay + gh from GitHub's official repo |
| GitHub | `gh auth login` (browser) → `gh auth setup-git` | same; `GH_TOKEN` skips the prompt |
| Dotfiles | clones with submodules, then **delegates to `dotfiles/install.sh`** | clones, then mirrors it: oh-my-zsh (unattended), `~/.zshrc` + `~/.zprofile` symlinks, tmux theme into `~/.config/tmux/`, `chsh` to zsh |
| Git identity | `~/.gitconfig` include → `dotfiles/git/gitconfig` (`useConfigOnly` guardrail) | same |
| Vault | clone + seed device-local Obsidian Git `data.json` from the tracked template | same |
| Claude Code | native installer (skipped if present) | same; skipped on 32-bit ARM with a warning |
| Obsidian app | brew cask | Flatpak (flathub); skipped on headless hosts |

The script never reimplements what the dotfiles repo already does — on macOS it hands
off to `dotfiles/install.sh` (Brewfile, oh-my-zsh ordering traps, Terminal.app profile),
and on Linux it follows the documented clawscan pattern: link the tracked tmux files by
hand, put per-host identity in `~/.config/tmux/local.conf`.

## Prerequisites

- **macOS:** nothing. A factory-fresh machine works — run the one-liner in Terminal.app.
- **Linux:** `curl` and (unless root) `sudo`. Minimal containers: `apt-get update && apt-get install -y curl sudo` first.
- The dotfiles and vault repos are **private**, so the GitHub login step must succeed
  before the clones; that's why this repo is public and they aren't.

## Environment variables

| Var | Effect |
|---|---|
| `MACHINE_SETUP_PROJECTS` | where repos land (default `~/claw/projects`) |
| `GH_TOKEN` | skip interactive GitHub login (containers/CI) |
| `GH_OWNER` | GitHub account to clone from (default `pauli3j`) |
| `DOTFILES_SKIP_TERMINAL=1` etc. | passed through to `dotfiles/install.sh` on macOS |

## After it runs (manual, GUI)

1. Obsidian → "Open folder as vault" → the cloned vault → trust + enable community
   plugins. Obsidian Git then auto-backs-up every 15 min and pulls on launch.
2. macOS: open a new Terminal tab — "Paulie" profile, banner, and tmux status-bar
   glyphs should render as shapes, not tofu boxes.
3. Linux: log out/in for the zsh login shell; optional per-host tmux colors/prefix in
   `~/.config/tmux/local.conf` (see `local.conf.example` in the tmux repo).

## Testing in a container

```bash
GH_TOKEN=$(gh auth token) docker run -e GH_TOKEN -it --rm ubuntu:24.04 bash -c '
  apt-get update && apt-get install -y curl sudo ca-certificates &&
  curl -fsSL https://raw.githubusercontent.com/pauli3j/machine-setup/main/setup.sh | bash'
```

Exercises the apt branch, token auth, root path (`SUDO=""`), headless Obsidian skip,
and the Linux Claude Code install. Swap in `fedora:latest` (with `dnf install -y curl sudo`)
for the dnf branch.

## Lint

```bash
bash -n setup.sh && shellcheck setup.sh
```

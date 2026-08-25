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

| Step | macOS | Linux (apt / dnf / pacman) |
|---|---|---|
| Dev tools | Homebrew (installs Xcode CLT itself) | git, curl, build tools via the package manager |
| Base packages | via the dotfiles `Brewfile` | zsh, tmux, jq, cowsay + gh (GitHub's repo on apt/dnf; `github-cli` from `[extra]` on Arch) |
| GitHub | `gh auth login` (browser) → `gh auth setup-git` | same; `GH_TOKEN` skips the prompt |
| Desktop | Terminal.app profile via dotfiles/install.sh | Omarchy hosts: delegated to `dotfiles/omarchy/install.sh` (Hyprland, shell, theme, terminals) |
| Dotfiles | clones with submodules, then **delegates to `dotfiles/install.sh`** | clones, then mirrors it: oh-my-zsh (unattended), `~/.zshrc` + `~/.zprofile` symlinks, tmux theme into `~/.config/tmux/`, `chsh` to zsh |
| Git identity | `~/.gitconfig` include → `dotfiles/git/gitconfig` (`useConfigOnly` guardrail) | same |
| Vault | clone + seed device-local Obsidian Git `data.json` from the tracked template | same |
| Claude Code | native installer (skipped if present) — **binary only**, see step 5 | same; skipped on 32-bit ARM with a warning |
| Obsidian app | brew cask | Flatpak (flathub); skipped on headless hosts |
| Claude workspace + VPN | **opt-in** (`MACHINE_SETUP_WORKSPACE=1`): hub skeleton + permission guardrails, then a checklist | same, without the macOS VPN line |

The script never reimplements what the dotfiles repo already does — on macOS it hands
off to `dotfiles/install.sh` (Brewfile, oh-my-zsh ordering traps, Terminal.app profile),
and on Linux it follows the documented clawscan pattern: link the tracked tmux files by
hand, put per-host identity in `~/.config/tmux/local.conf`.

## Prerequisites

- **macOS:** nothing. A factory-fresh machine works — run the one-liner in Terminal.app.
- **Linux:** `curl` and (unless root) `sudo`. Minimal containers: `apt-get update && apt-get install -y curl sudo` first
  (Arch: `pacman -Syu --noconfirm curl sudo`). Debian/Ubuntu, Fedora, and Arch/Omarchy are all handled.
- The dotfiles and vault repos are **private**, so the GitHub login step must succeed
  before the clones; that's why this repo is public and they aren't.

## Environment variables

| Var | Effect |
|---|---|
| `MACHINE_SETUP_PROJECTS` | where repos land. Unset, an **existing** dotfiles checkout wins: `~/Work`, then `~/clawh/projects`, then `~/claw/projects`; a fresh box gets `~/claw/projects` |
| `MACHINE_SETUP_VAULT` | the vault checkout. Unset, searches `<projects>/obsidian-vault` then `~/Documents/obsidian-vault` |
| `GH_TOKEN` | skip interactive GitHub login (containers/CI) |
| `GH_OWNER` | GitHub account to clone from (default `pauli3j`) |
| `DOTFILES_SKIP_TERMINAL=1` etc. | passed through to `dotfiles/install.sh` on macOS |
| `MACHINE_SETUP_WORKSPACE=1` | opt into the Claude workspace + VPN add-on (step 8). Off by default — a plain bootstrap shouldn't write permission policy |

## After it runs (manual, GUI)

1. Obsidian → "Open folder as vault" → the cloned vault → trust + enable community
   plugins. Obsidian Git then auto-backs-up every 15 min and pulls on launch.
2. macOS: **quit and reopen Terminal.app** — windows opened before the run keep their
   old profile, and the freshly installed Nerd Font only joins glyph fallback after a
   relaunch. A running tmux session survives the quit (`tmux attach` afterwards). Then
   the "Paulie" profile, banner, and tmux status-bar glyphs should render as shapes,
   not tofu boxes.
3. Linux: log out/in for the zsh login shell; optional per-host tmux colors/prefix in
   `~/.config/tmux/local.conf` (see `local.conf.example` in the tmux repo).
4. **Claude Code workspace.** The base script installs the Claude Code *binary* and nothing
   else — no charter, no permission guardrails, no skills, no MCP endpoints. A machine that
   has only run the base script has a Claude that does not know the house conventions and
   cannot reach any tenant.

   Run the add-on to get the automatable half:

   ```bash
   MACHINE_SETUP_WORKSPACE=1 bash setup.sh
   ```

   It creates the hub skeleton (`reports/`, `scratch/`, `~/.claude/skills/`) and writes
   `<hub>/.claude/settings.json` with the **`git init` and `git config --global` denials** —
   which exist because an unconfigured git invents a `user@hostname` identity instead of
   erroring, and that once put a work email in a personal repo. An existing `settings.json`
   is never overwritten. Note that a machine with no `settings.json` has no policy at all,
   only whatever `settings.local.json` a session happened to accumulate.

   Then, by hand: copy `~/.claude/CLAUDE.md`, `<hub>/CLAUDE.md`, and `~/.claude/skills/`
   **from an already-configured machine rather than rewriting them** — that prose reached its
   current form deliberately and reconstructing it from memory loses that. Register the MCP
   endpoints last; that needs a per-device token, and a rebuilt machine's old token should be
   revoked. Values and the token procedure are in the private vault runbooks, not here.
5. macOS, if this machine needs the home VPN: install **WireGuard** from the Mac App
   Store (id `1451685025`) — it is not brew-installable, and `mas` cannot install an app
   the Apple ID has never acquired, so this stays manual. Then add the tunnel in the app
   and enroll its public key on the firewall. The tunnel config is deliberately **not**
   in any repo and is not symlinked out of `dotfiles` like everything else here: it
   embeds a private key. Procedure and the per-device values live in the private vault
   runbook, not in this public repo.

## Testing in a container

```bash
GH_TOKEN=$(gh auth token) docker run -e GH_TOKEN -it --rm ubuntu:24.04 bash -c '
  apt-get update && apt-get install -y curl sudo ca-certificates &&
  curl -fsSL https://raw.githubusercontent.com/pauli3j/machine-setup/main/setup.sh | bash'
```

Exercises the apt branch, token auth, root path (`SUDO=""`), headless Obsidian skip,
and the Linux Claude Code install. Swap in `fedora:latest` (with `dnf install -y curl sudo`)
for the dnf branch, or `archlinux:latest` for pacman:

```bash
GH_TOKEN=$(gh auth token) docker run -e GH_TOKEN -it --rm archlinux:latest bash -c '
  pacman -Syu --noconfirm curl sudo &&
  curl -fsSL https://raw.githubusercontent.com/pauli3j/machine-setup/main/setup.sh | bash'
```

The Arch image runs as root, so that run also covers `SUDO=""` through the pacman branch.
Note it exercises the *container* path only: the two shell caches that make `chsh` look like
a no-op (a running tmux server, the systemd user session) need a real desktop to reproduce.

## Lint

```bash
bash -n setup.sh && shellcheck setup.sh
```

#!/usr/bin/env bash
# Xzutll's Hyprland dotfiles installer (Arch Linux)
# Made With Claude Code! (BETA VERSION)
#
#   git clone https://github.com/xzutll/config && cd config && ./install.sh
#
# Options
#   --dry-run    Show what would be done without changing anything
#   --minimal    Skip optional apps (gimp, mpv, flatpak)
#   --no-deps    Skip package installation, only deploy config files
#   --copy       Copy files instead of creating symlinks
#   -y, --yes    Don't ask for confirmation
#   -h, --help   Show this help

set -euo pipefail

# ─────────────────────────────── Settings ───────────────────────────────
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
BACKUP_DIR="$CONFIG_HOME/dotfiles-backup-$(date +%Y%m%d-%H%M%S)-$$"

# Repo folders to deploy into ~/.config
CONFIG_DIRS=(hypr waybar rofi kitty fcitx5)
# fcitx5 rewrites its own config at runtime, which would keep dirtying the repo if linked → always copy
ALWAYS_COPY=(fcitx5)

# Required packages (from the README + commands actually called in the configs)
CORE_PKGS=(
  # Desktop
  hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk hyprpolkitagent
  waybar rofi dunst kitty dolphin awww
  # Themes / fonts
  nwg-look qt6ct adw-gtk-theme glib2 ttf-jetbrains-mono-nerd noto-fonts-cjk
  # Korean input (QT_IM_MODULE=fcitx requires fcitx5-qt)
  fcitx5 fcitx5-configtool fcitx5-hangul fcitx5-qt fcitx5-gtk
  # Audio (waybar pulseaudio module, wpctl)
  pipewire pipewire-pulse wireplumber pavucontrol
  # Tools used by keybinds (screenshots, clipboard, media, brightness)
  grim slurp swappy wl-clipboard playerctl brightnessctl
  # Shell
  zsh
)
OPTIONAL_PKGS=(gimp mpv flatpak)

# ─────────────────────────────── Options ───────────────────────────────
DRY_RUN=0 MINIMAL=0 NO_DEPS=0 COPY=0 YES=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --minimal) MINIMAL=1 ;;
    --no-deps) NO_DEPS=1 ;;
    --copy)    COPY=1 ;;
    -y|--yes)  YES=1 ;;
    -h|--help) sed -n '2,13p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg (see --help)"; exit 1 ;;
  esac
done

# ─────────────────────────────── Output helpers ───────────────────────────────
if [[ -t 1 ]]; then
  C_BLUE=$'\e[34m' C_GREEN=$'\e[32m' C_YELLOW=$'\e[33m' C_RED=$'\e[31m' C_BOLD=$'\e[1m' C_RESET=$'\e[0m'
else
  C_BLUE='' C_GREEN='' C_YELLOW='' C_RED='' C_BOLD='' C_RESET=''
fi
step() { echo; echo "${C_BOLD}${C_BLUE}==>${C_RESET}${C_BOLD} $*${C_RESET}"; }
info() { echo "  ${C_GREEN}✓${C_RESET} $*"; }
warn() { echo "  ${C_YELLOW}!${C_RESET} $*"; WARNINGS+=("$*"); }
die()  { echo "${C_RED}✗ $*${C_RESET}" >&2; exit 1; }
WARNINGS=()

run() {  # Run a command (only print it in dry-run mode)
  if (( DRY_RUN )); then
    echo "  ${C_YELLOW}[dry-run]${C_RESET} $*"
  else
    "$@"
  fi
}

confirm() {
  (( YES || DRY_RUN )) && return 0
  local reply
  read -r -p "  $1 [Y/n] " reply
  [[ -z "$reply" || "$reply" =~ ^[Yy] ]]
}

# ─────────────────────────────── Pre-flight checks ───────────────────────────────
step "Checking environment"
[[ $EUID -ne 0 ]] || die "Do not run as root. sudo is used only when needed."
command -v pacman >/dev/null || die "pacman not found. This script only supports Arch Linux based systems."
for d in "${CONFIG_DIRS[@]}"; do
  [[ -d "$REPO_DIR/$d" ]] || die "Folder '$d' not found in the repo. Run this from the repo root: $REPO_DIR"
done
info "Repo: $REPO_DIR"
info "Install target: $CONFIG_HOME"
(( DRY_RUN )) && warn "Dry-run mode: nothing will actually be changed"

# ─────────────────────────────── Packages ───────────────────────────────
ensure_paru() {
  if command -v paru >/dev/null; then
    info "paru is already installed"
    return
  fi
  warn "paru not found, installing it from the AUR (paru-bin)"
  run sudo pacman -S --needed --noconfirm base-devel git
  local tmp
  tmp="$(mktemp -d)"
  run git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
  if (( DRY_RUN )); then
    echo "  ${C_YELLOW}[dry-run]${C_RESET} (cd $tmp/paru-bin && makepkg -si --noconfirm)"
  else
    (cd "$tmp/paru-bin" && makepkg -si --noconfirm)
  fi
  rm -rf "$tmp"
}

install_packages() {
  local pkgs=("${CORE_PKGS[@]}")
  (( MINIMAL )) || pkgs+=("${OPTIONAL_PKGS[@]}")

  # Avoid partial upgrades on Arch (pacman -Sy + install): do a full upgrade first
  step "Updating the system (pacman -Syu)"
  run sudo pacman -Syu

  step "Sorting packages (official repos / AUR)"
  local repo_pkgs=() aur_pkgs=() missing=() p
  for p in "${pkgs[@]}"; do
    if pacman -Qq "$p" &>/dev/null; then
      info "$p (already installed)"
    elif pacman -Si "$p" &>/dev/null; then
      repo_pkgs+=("$p")
    else
      aur_pkgs+=("$p")   # Not in the official repos → try the AUR
    fi
  done

  if (( ${#repo_pkgs[@]} )); then
    step "Installing from official repos: ${repo_pkgs[*]}"
    run sudo pacman -S --needed "${repo_pkgs[@]}"
  fi

  if (( ${#aur_pkgs[@]} )); then
    step "Installing from the AUR: ${aur_pkgs[*]}"
    ensure_paru
    local found=()
    for p in "${aur_pkgs[@]}"; do
      if (( DRY_RUN )) && ! command -v paru >/dev/null; then
        found+=("$p")                                  # dry-run without paru → can't check, assume found
      elif paru -Si "$p" &>/dev/null; then
        found+=("$p")
      else
        missing+=("$p")
      fi
    done
    (( ${#found[@]} )) && run paru -S --needed "${found[@]}"
  fi

  for p in "${missing[@]}"; do
    warn "Package not found, skipped: $p (check whether it was renamed)"
  done
}

if (( NO_DEPS )); then
  step "Skipping package installation (--no-deps)"
else
  install_packages
fi

# ─────────────────────────────── Deploy config files ───────────────────────────────
is_in() { local x="$1"; shift; for e in "$@"; do [[ "$e" == "$x" ]] && return 0; done; return 1; }

step "Deploying config files"
if ! confirm "Existing configs will be backed up to $BACKUP_DIR and replaced. Continue?"; then
  die "Cancelled."
fi
run mkdir -p "$CONFIG_HOME"

for d in "${CONFIG_DIRS[@]}"; do
  src="$REPO_DIR/$d"
  dst="$CONFIG_HOME/$d"

  # Already a symlink to this repo → leave it
  if [[ -L "$dst" && "$(readlink -f "$dst")" == "$(readlink -f "$src")" ]]; then
    info "$d: already linked"
    continue
  fi

  # Copy target whose contents are already identical → leave it
  if [[ -d "$dst" && ! -L "$dst" ]] && { (( COPY )) || is_in "$d" "${ALWAYS_COPY[@]}"; } \
     && diff -rq "$src" "$dst" &>/dev/null; then
    info "$d: already up to date"
    continue
  fi

  # Back up the existing config
  if [[ -e "$dst" || -L "$dst" ]]; then
    run mkdir -p "$BACKUP_DIR"
    run mv "$dst" "$BACKUP_DIR/$d"
    info "$d: backed up existing config → $BACKUP_DIR/$d"
  fi

  if (( COPY )) || is_in "$d" "${ALWAYS_COPY[@]}"; then
    run cp -r "$src" "$dst"
    info "$d: copied"
  else
    run ln -s "$src" "$dst"
    info "$d: linked ($dst → $src)"
  fi
done

# Make scripts executable
while IFS= read -r -d '' script; do
  run chmod +x "$script"
done < <(find "$REPO_DIR" -path "$REPO_DIR/.git" -prune -o -name '*.sh' -type f -print0)

# ─────────────────────────────── Environment checks ───────────────────────────────
step "Checking your setup (reported only, nothing is changed automatically)"

# NVIDIA-specific environment variables
if grep -q 'LIBVA_DRIVER_NAME", "nvidia' "$REPO_DIR/hypr/hyprland.lua"; then
  if command -v lspci >/dev/null && ! lspci | grep -qi 'nvidia'; then
    warn "No NVIDIA GPU detected. Remove the LIBVA_DRIVER_NAME and __GLX_VENDOR_LIBRARY_NAME lines from hypr/hyprland.lua"
  else
    info "Keeping NVIDIA environment variables"
  fi
fi

# Monitor name
if grep -q 'output = "DP-1"' "$REPO_DIR/hypr/hyprland.lua"; then
  warn "The monitor is hardcoded to DP-1 / 1920x1080@165. Check your monitor name with 'hyprctl monitors' after starting Hyprland"
fi

# Power menu script that isn't in the repo
if grep -q 'rofi/files/powermenu' "$REPO_DIR/waybar/config.jsonc" \
   && [[ ! -e "$CONFIG_HOME/rofi/files/powermenu/type-1/powermenu.sh" ]]; then
  warn "~/.config/rofi/files/powermenu/type-1/powermenu.sh used by the Waybar power button is missing (not included in the repo)"
fi

# Default shell
if [[ "$(basename "${SHELL:-}")" != "zsh" ]] && command -v zsh >/dev/null; then
  info "To make zsh your default shell: chsh -s \"$(command -v zsh)\""
fi

# ─────────────────────────────── Done ───────────────────────────────
step "Done"
if [[ -d "$BACKUP_DIR" ]]; then
  info "Backup of previous configs: $BACKUP_DIR"
fi
if (( ${#WARNINGS[@]} )); then
  echo
  echo "${C_BOLD}Things to check:${C_RESET}"
  for w in "${WARNINGS[@]}"; do echo "  ${C_YELLOW}!${C_RESET} $w"; done
fi
echo
echo "If you're inside Hyprland, apply it with 'hyprctl reload && hyprctl configerrors'."
echo "Otherwise, log out and log back in to Hyprland."

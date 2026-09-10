#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

PASS="[${GREEN}✓${NC}]"
FAIL="[${RED}✗${NC}]"
WARN="[${YELLOW}!${NC}]"

ALL_PASSED=true
INSTALL_MODE=false

usage() {
	cat <<EOF
Usage: $0 [OPTIONS]

Check and optionally install dependencies for monkey-hyprland.

OPTIONS
  -i, --install    Install missing dependencies
  -h, --help       Show this help

Exit code: 1 if any required dependency is missing, 0 otherwise.
EOF
	exit 0
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	-i | --install) INSTALL_MODE=true ;;
	-h | --help) usage ;;
	*)
		echo "Unknown option: $1"
		usage
		;;
	esac
	shift
done

# ──────────────────────────── helpers ────────────────────────────

check_bin() {
	if command -v "$1" &>/dev/null; then
		echo -e "  ${PASS} ${2:-$1}"
		return 0
	else
		echo -e "  ${FAIL} ${2:-$1}"
		return 1
	fi
}

# Same as check_bin but accepts multiple alternatives and falls back to
# /usr/lib and /usr/libexec (D-Bus services such as the desktop portals and
# polkit agents usually live outside PATH).
check_bin_ext() {
	local label="$1"
	shift
	for b in "$@"; do
		if command -v "$b" &>/dev/null || [[ -x "/usr/lib/$b" ]] || [[ -x "/usr/libexec/$b" ]]; then
			echo -e "  ${PASS} $label ($b)"
			return 0
		fi
	done
	echo -e "  ${FAIL} $label"
	return 1
}

# Pure availability test used after --install: PATH or /usr/lib* lookup.
bin_req_ok() {
	local b="$1"
	if [[ "$b" == "notif" ]]; then
		command -v mako &>/dev/null && return 0
		command -v dunst &>/dev/null && return 0
		return 1
	fi
	if command -v "$b" &>/dev/null; then return 0; fi
	for p in "/usr/lib/$b" "/usr/libexec/$b"; do
		[[ -x "$p" ]] && return 0
	done
	return 1
}

os_detect() {
	case "$(uname -s)" in
	Linux)
		if [ -f /etc/os-release ]; then
			. /etc/os-release
			case "$ID" in
			ubuntu | debian | linuxmint | pop | elementary | zorin) echo "debian" ;;
			arch | manjaro | endeavouros) echo "arch" ;;
			opensuse | opensuse-leap | opensuse-tumbleweed | opensuse-microos | suse | sles) echo "opensuse" ;;
			centos | rhel | fedora | rocky | almalinux | ol) echo "centos" ;;
			*) echo "linux-unknown" ;;
			esac
		else
			echo "linux-unknown"
		fi
		;;
	*) echo "unknown" ;;
	esac
}

OS=$(os_detect)

sudo_cmd() {
	if command -v sudo &>/dev/null; then
		sudo "$@"
	else
		"$@"
	fi
}

install_pkg() {
	if ! $INSTALL_MODE; then return 1; fi
	case "$OS" in
	debian) sudo_cmd apt-get install -y "${*}" ;;
	arch) sudo_cmd pacman -S --noconfirm "${@}" ;;
	opensuse) sudo_cmd zypper --non-interactive install -y "${@}" ;;
	centos) sudo_cmd dnf install -y "${@}" ;;
	*) return 1 ;;
	esac
}

get_install_hint() {
	case "$OS" in
	debian) echo "sudo apt-get install ${*}" ;;
	opensuse) echo "sudo zypper install ${*}" ;;
	centos) echo "sudo dnf install ${*}" ;;
	arch) echo "sudo pacman -S ${*}" ;;
	linux-unknown) echo "install ${*} manually" ;;
	*) echo "install ${*} manually" ;;
	esac
}

# ────────────────── dependency definitions ──────────────────

REQUIRED_BINS=(hyprctl waybar wezterm wofi grim slurp wl-copy wlogout wpctl hyprpaper hypridle)
# D-Bus services that may live outside PATH (/usr/lib, /usr/libexec). "notif"
# is special: it accepts mako OR dunst (any one notification daemon).
REQUIRED_EXT_BINS=(xdg-desktop-portal-hyprland xdg-desktop-portal-gtk hyprpolkitagent notif)
RECOMMENDED_BINS=(nm-applet hyprlock brightnessctl pavucontrol nm-connection-editor hyprpicker hyprsunset)

# Human-readable name for a dependency binary.
dep_name() {
	case "$1" in
	hyprctl) echo "hyprctl (ships with Hyprland)" ;;
	wezterm) echo "wezterm (default terminal)" ;;
	wofi) echo "wofi (app launcher)" ;;
	grim) echo "grim (screenshot)" ;;
	slurp) echo "slurp (region select)" ;;
	wl-copy) echo "wl-clipboard (wl-copy)" ;;
	wlogout) echo "wlogout (power menu)" ;;
	wpctl) echo "wireplumber (wpctl)" ;;
	hyprpaper) echo "hyprpaper (wallpaper)" ;;
	hypridle) echo "hypridle (idle management)" ;;
	xdg-desktop-portal-hyprland) echo "xdg-desktop-portal-hyprland (capture/sharing portal)" ;;
	xdg-desktop-portal-gtk) echo "xdg-desktop-portal-gtk (file-chooser portal)" ;;
	hyprpolkitagent) echo "hyprpolkitagent (polkit auth agent)" ;;
	notif) echo "notification daemon (mako/dunst)" ;;
	nm-applet) echo "nm-applet (tray network manager)" ;;
	hyprlock) echo "hyprlock (lock screen)" ;;
	hyprpicker) echo "hyprpicker (color picker)" ;;
	hyprsunset) echo "hyprsunset (color temperature)" ;;
	nm-connection-editor) echo "nm-connection-editor" ;;
	*) echo "$1" ;;
	esac
}

# Package name for a binary on the detected OS. Only entries that differ
# from the binary name need a case arm; everything else falls through.
pkg_name() {
	local bin="$1"
	case "$OS:$bin" in
	# Sentinel: notification daemon — install mako by default
	*:notif) echo "mako" ;;
	# Debian / apt
	debian:wl-copy) echo "wl-clipboard" ;;
	debian:wpctl) echo "wireplumber" ;;
	debian:nm-applet) echo "network-manager-gnome" ;;
	debian:nm-connection-editor) echo "nm-connection-editor" ;;
	# Arch / pacman
	arch:wl-copy) echo "wl-clipboard" ;;
	arch:wpctl) echo "wireplumber" ;;
	arch:nm-applet) echo "network-manager-applet" ;;
	arch:nm-connection-editor) echo "nm-connection-editor" ;;
	# openSUSE / zypper
	opensuse:wl-copy) echo "wl-clipboard" ;;
	opensuse:wpctl) echo "wireplumber" ;;
	opensuse:nm-applet) echo "NetworkManager-applet" ;;
	opensuse:nm-connection-editor) echo "nm-connection-editor" ;;
	# CentOS-family / dnf
	centos:wl-copy) echo "wl-clipboard" ;;
	centos:wpctl) echo "wireplumber" ;;
	centos:nm-applet) echo "NetworkManager-applet" ;;
	*)
		echo "$bin"
		;;
	esac
}

# ──────────────────── main ────────────────────

echo -e "${BOLD}monkey-hyprland dependency check${NC}"
echo ""

echo -e "${BOLD}Hyprland version${NC}"
if command -v Hyprland &>/dev/null; then
	out=$(Hyprland --version 2>/dev/null)
	ver=$(echo "$out" | grep -m1 -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' || true)
	if [[ -n "$ver" ]]; then
		major=${ver%%.*}
		minor=$(echo "$ver" | cut -d. -f2)
		if ((major > 0 || (major == 0 && minor >= 55))); then
			echo -e "  ${PASS} Hyprland ${ver}"
		else
			echo -e "  ${FAIL} Hyprland ${ver} (need >= 0.55 for Lua config support)"
			ALL_PASSED=false
		fi
	else
		echo -e "  ${PASS} Hyprland (version string unparsable: $(echo "$out" | head -1))"
	fi
	if echo "$out" | grep -qi lua; then
		echo -e "  ${PASS} Lua config support built in"
	else
		echo -e "  ${WARN} version string does not mention Lua — check that your build supports the hl Lua config API"
	fi
elif command -v hyprctl &>/dev/null; then
	echo -e "  ${WARN} Hyprland binary not found, but hyprctl is available"
else
	echo -e "  ${FAIL} Hyprland (not found)"
	ALL_PASSED=false
fi
echo ""

# Check the OS
echo -e "${BOLD}Platform${NC}"
echo -e "  OS: ${CYAN}$(uname -s)${NC}"
case "$OS" in
debian) echo -e "  Package manager: ${CYAN}apt${NC}" ;;
opensuse) echo -e "  Package manager: ${CYAN}zypper${NC}" ;;
centos) echo -e "  Package manager: ${CYAN}dnf${NC}" ;;
arch) echo -e "  Package manager: ${CYAN}pacman${NC}" ;;
*) echo -e "  ${WARN} Unsupported OS — install dependencies manually" ;;
esac
echo ""

# ──── required tools ────
echo -e "${BOLD}Required tools${NC}"
echo "  (compositor/bar/terminal/launcher/screenshot/portals/polkit/notif/audio/wallpaper/idle)"
MISSING_REQUIRED=()
for bin in "${REQUIRED_BINS[@]}"; do
	if check_bin "$bin" "$(dep_name "$bin")"; then
		:
	else
		MISSING_REQUIRED+=("$bin")
	fi
done
for bin in "${REQUIRED_EXT_BINS[@]}"; do
	if [[ "$bin" == "notif" ]]; then
		candidates=("mako" "dunst")
	else
		candidates=("$bin")
	fi
	if check_bin_ext "$(dep_name "$bin")" "${candidates[@]}"; then
		:
	else
		MISSING_REQUIRED+=("$bin")
	fi
done
echo ""

if $INSTALL_MODE && [[ ${#MISSING_REQUIRED[@]} -gt 0 ]]; then
	echo -e "${YELLOW}Installing: ${MISSING_REQUIRED[*]}...${NC}"
	pkgs=()
	for b in "${MISSING_REQUIRED[@]}"; do pkgs+=("$(pkg_name "$b")"); done
	if install_pkg "${pkgs[@]}"; then
		MISSING_REQUIRED=()
		for bin in "${REQUIRED_BINS[@]}" "${REQUIRED_EXT_BINS[@]}"; do
			if bin_req_ok "$bin"; then
				echo -e "  ${PASS} $(dep_name "$bin") installed"
			else
				MISSING_REQUIRED+=("$bin")
				echo -e "  ${FAIL} $(dep_name "$bin") still missing"
			fi
		done
		if [[ ${#MISSING_REQUIRED[@]} -eq 0 ]]; then
			echo -e "${GREEN}All required tools now available.${NC}"
		else
			echo -e "${RED}Not in system repos — install manually: wezterm (https://wezterm.org/installation), hyprlock (https://github.com/hyprwm/hyprlock), xdg-desktop-portal-hyprland, hyprpolkitagent, hyprpaper, hypridle (on Arch all of these are in the official repo)${NC}"
		fi
	else
		echo -e "${RED}Install command failed. Run: $(get_install_hint "${pkgs[*]}")${NC}"
	fi
	echo ""
fi

if [[ ${#MISSING_REQUIRED[@]} -gt 0 ]]; then
	ALL_PASSED=false
fi

# ──── recommended tools ────
echo -e "${BOLD}Recommended tools${NC}"
echo "  (Missing won't block monkey-hyprland, but will degrade tray / lock / brightness experience)"
MISSING_RECOMMENDED=()
for bin in "${RECOMMENDED_BINS[@]}"; do
	if ! check_bin "$bin" "$(dep_name "$bin")"; then
		MISSING_RECOMMENDED+=("$bin")
	fi
done
echo ""

if $INSTALL_MODE && [[ ${#MISSING_RECOMMENDED[@]} -gt 0 ]]; then
	echo -e "${YELLOW}Installing: ${MISSING_RECOMMENDED[*]}...${NC}"
	pkgs=()
	for b in "${MISSING_RECOMMENDED[@]}"; do pkgs+=("$(pkg_name "$b")"); done
	if install_pkg "${pkgs[@]}"; then
		echo -e "${GREEN}Done.${NC}"
	else
		echo -e "${RED}Failed. Run: $(get_install_hint "${pkgs[*]}")${NC}"
	fi
	echo ""
fi

# ──── fonts ────
echo -e "${BOLD}Fonts (optional)${NC}"
echo "  (waybar icons use Nerd Font glyphs)"
if fc-list 2>/dev/null | grep -qi "nerd"; then
	echo -e "  ${PASS} Nerd Font found"
else
	echo -e "  ${WARN} No Nerd Font detected — waybar icons may render as boxes"
	echo -e "    https://github.com/ryanoasis/nerd-fonts"
fi
echo ""

# ──── config files ────
echo -e "${BOLD}Config files${NC}"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

HYPR_CONFIG="${HOME}/.config/hypr/hyprland.lua"
if [[ -L "$HYPR_CONFIG" ]]; then
	TARGET=$(readlink -f "$HYPR_CONFIG" 2>/dev/null || readlink "$HYPR_CONFIG")
	echo -e "  ${PASS} hyprland.lua → ${TARGET}"
elif [[ -f "$HYPR_CONFIG" ]]; then
	echo -e "  ${WARN} hyprland.lua exists but is not a symlink"
else
	echo -e "  ${FAIL} hyprland.lua not found (run: ln -sf ${SCRIPT_DIR}/hyprland.lua ~/.config/hypr/hyprland.lua)"
	ALL_PASSED=false
fi

WAYBAR_DIR="${HOME}/.config/waybar"
if [[ -L "$WAYBAR_DIR" ]]; then
	TARGET=$(readlink -f "$WAYBAR_DIR" 2>/dev/null || readlink "$WAYBAR_DIR")
	echo -e "  ${PASS} waybar → ${TARGET}"
elif [[ -f "$WAYBAR_DIR/config.jsonc" && -f "$WAYBAR_DIR/style.css" ]]; then
	if [[ -f "${SCRIPT_DIR}/waybar/config.jsonc" && "$WAYBAR_DIR/config.jsonc" -ef "${SCRIPT_DIR}/waybar/config.jsonc" ]]; then
		echo -e "  ${PASS} waybar → ${SCRIPT_DIR}/waybar"
	else
		echo -e "  ${WARN} waybar is a plain directory (not a symlink to ${SCRIPT_DIR}/waybar)"
	fi
else
	echo -e "  ${FAIL} waybar config not found (run: ln -sf ${SCRIPT_DIR}/waybar ~/.config/waybar)"
	ALL_PASSED=false
fi

if [[ -d "${HOME}/.config/wlogout" ]] || command -v wlogout &>/dev/null; then
	echo -e "  ${PASS} wlogout present (power menu)"
else
	echo -e "  ${WARN} wlogout config dir not found (waybar power button needs it)"
fi
echo ""

# ──── summary ────
if $ALL_PASSED; then
	echo -e "${GREEN}${BOLD}All required dependencies satisfied.${NC}"
	exit 0
else
	echo -e "${RED}${BOLD}Some required dependencies are missing.${NC}"
	if ! $INSTALL_MODE; then
		echo -e "Run ${CYAN}$0 --install${NC} to install them automatically."
	fi
	exit 1
fi

#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# monkey-hyprland dependency check
#
# The check framework lives in scripts/ (a `git subtree` of
# github.com/QMonkey/monkey-scripts) — this file only declares WHAT to check.
# ──────────────────────────────────────────────────────────────

. "$(dirname "${BASH_SOURCE[0]:-$0}")/scripts/checkhealth.sh" || {
	echo "monkey-scripts not found — update this checkout (git pull / re-clone)," >&2
	echo "or run install.sh, which bootstraps monkey-scripts itself." >&2
	exit 1
}

# ──────────────────────── identity ────────────────────────
PROJECT=monkey-hyprland

# ──────────────────────── Hyprland version probe ────────────────────────
# Printed between the title and Platform (the original's print_header).
# Failures cannot touch REQUIRED_FAILURES here — run_required_checks resets
# the counter right after — so they are folded in by checkhealth_extra.
HYPR_VERSION_FAILED=0
print_header_extra() {
	echo -e "${BOLD}Hyprland version${NC}"
	if have_native_cmd Hyprland; then
		local out ver major minor
		out=$(Hyprland --version 2>/dev/null)
		# head -n1: the version line can carry the number twice and -o prints
		# EVERY match on it — "0.56.2\n0.56.2" then reached the arithmetic
		# compare and died with a syntax error, always failing the check
		# (observed on Hyprland 0.56.2).
		ver=$(echo "$out" | grep -m1 -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -n1)
		if [[ -n "$ver" ]]; then
			major=${ver%%.*}
			minor=$(echo "$ver" | cut -d. -f2)
			if ((major > 0 || (major == 0 && minor >= 55))); then
				ok "Hyprland ${ver}"
			else
				fail "Hyprland ${ver} (need >= 0.55 for Lua config support)"
				HYPR_VERSION_FAILED=1
			fi
		else
			ok "Hyprland (version string unparsable: $(echo "$out" | head -1))"
		fi
		if echo "$out" | grep -qi lua; then
			ok "Lua config support built in"
		else
			warn "version string does not mention Lua — check that your build supports the hl Lua config API"
		fi
	elif have_native_cmd hyprctl; then
		warn "Hyprland binary not found, but hyprctl is available"
	else
		fail "Hyprland (not found)"
		HYPR_VERSION_FAILED=1
	fi
	echo ""
}

checkhealth_extra() {
	if [ "$HYPR_VERSION_FAILED" = 1 ]; then
		REQUIRED_FAILURES=$((REQUIRED_FAILURES + 1))
	fi
}

# ──────────────────────── required ────────────────────────
# Binary lists kept alongside the specs: the post-install re-probe below
# walks them (not the spec list) and prints one line per binary.
REQUIRED_BINS=(hyprctl waybar wezterm wofi grim slurp wl-copy wlogout wpctl hyprpaper hypridle fcitx5)
# D-Bus services that may live outside PATH (/usr/lib, /usr/libexec).
# "notif" is special: it accepts mako OR dunst.
REQUIRED_EXT_BINS=(xdg-desktop-portal-hyprland xdg-desktop-portal-gtk hyprpolkitagent notif)

REQUIRED_CHECKS=(
	"@header|Required tools"
	"@note|(compositor/bar/terminal/launcher/screenshot/portals/polkit/notif/audio/wallpaper/idle/input method)"
	"hyprctl|bin|hyprctl (ships with Hyprland)"
	"waybar|bin|waybar"
	"wezterm|bin|wezterm (default terminal)"
	"wofi|bin|wofi (app launcher)"
	"grim|bin|grim (screenshot)"
	"slurp|bin|slurp (region select)"
	"wl-copy|bin|wl-clipboard (wl-copy)"
	"wlogout|bin|wlogout (power menu)"
	"wpctl|bin|wireplumber (wpctl)"
	"hyprpaper|bin|hyprpaper (wallpaper)"
	"hypridle|bin|hypridle (idle management)"
	"fcitx5|bin|fcitx5 (input method framework)"
	"xdg-desktop-portal-hyprland|anyofext:xdg-desktop-portal-hyprland|xdg-desktop-portal-hyprland (capture/sharing portal)"
	"xdg-desktop-portal-gtk|anyofext:xdg-desktop-portal-gtk|xdg-desktop-portal-gtk (file-chooser portal)"
	"hyprpolkitagent|anyofext:hyprpolkitagent|hyprpolkitagent (polkit auth agent)"
	"notif|anyofext:mako dunst|notification daemon (mako/dunst)"
)

# Human-readable name for a dependency binary (used by the re-probe below).
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
	fcitx5) echo "fcitx5 (input method framework)" ;;
	xdg-desktop-portal-hyprland) echo "xdg-desktop-portal-hyprland (capture/sharing portal)" ;;
	xdg-desktop-portal-gtk) echo "xdg-desktop-portal-gtk (file-chooser portal)" ;;
	hyprpolkitagent) echo "hyprpolkitagent (polkit auth agent)" ;;
	notif) echo "notification daemon (mako/dunst)" ;;
	nm-applet) echo "nm-applet (tray network manager)" ;;
	hyprlock) echo "hyprlock (lock screen)" ;;
	hyprpicker) echo "hyprpicker (color picker)" ;;
	hyprsunset) echo "hyprsunset (color temperature)" ;;
	nm-connection-editor) echo "nm-connection-editor" ;;
	hyprland-dialog) echo "hyprland-guiutils (GUI helper dialogs/run/welcome)" ;;
	*) echo "$1" ;;
	esac
}

# Pure availability test used after --install: PATH or /usr/lib* lookup.
# "notif" accepts either notification daemon.
bin_req_ok() {
	local b="$1" p
	if [ "$b" = "notif" ]; then
		have_native_cmd mako && return 0
		have_native_cmd dunst && return 0
		return 1
	fi
	if have_native_cmd "$b"; then return 0; fi
	for p in "/usr/lib/$b" "/usr/libexec/$b"; do
		[ -x "$p" ] && return 0
	done
	return 1
}

# Package name for a binary on the detected OS. Only entries that differ
# from the binary name need a case arm; everything else falls through.
# Keyed by $OS: one id per distro. Ubuntu keeps hyprland-qtutils while
# Debian names it hyprland-guiutils, and Fedora has its own dnf row.
pkg_name() {
	local bin="$1"
	case "$OS:$bin" in
	# The GUI dialog helpers (upstream hyprland-qtutils): Debian, Arch and
	# openSUSE name the binary package hyprland-guiutils, Ubuntu
	# hyprland-qtutils.
	# Coverage varies per release (Ubuntu < 26.04, Debian trixie: absent)
	# — the availability probe degrades gracefully when missing.
	ubuntu:hyprland-dialog) echo "hyprland-qtutils" ;;
	debian:hyprland-dialog) echo "hyprland-guiutils" ;;
	arch:hyprland-dialog) echo "hyprland-guiutils" ;;
	opensuse:hyprland-dialog) echo "hyprland-guiutils" ;;
	# Sentinel: notification daemon — install mako by default
	# debian/ubuntu: the package is named mako-notifier and dunst is present
	# everywhere — dunst is the safe default. EPEL: dunst only.
	debian:notif | ubuntu:notif | centos:notif | fedora:notif) echo "dunst" ;;
	*:notif) echo "mako" ;;
	# hyprctl ships inside the compositor package on every distro
	*:hyprctl) echo "hyprland" ;;
	# Debian / apt
	debian:wl-copy) echo "wl-clipboard" ;;
	debian:wpctl) echo "wireplumber" ;;
	debian:nm-applet) echo "network-manager-gnome" ;;
	# nm-connection-editor is a binary of network-manager-gnome on
	# Debian/Ubuntu — there is no separate package
	debian:nm-connection-editor) echo "network-manager-gnome" ;;
	# Ubuntu / apt: same package names as Debian
	ubuntu:wl-copy) echo "wl-clipboard" ;;
	ubuntu:wpctl) echo "wireplumber" ;;
	ubuntu:nm-applet) echo "network-manager-gnome" ;;
	ubuntu:nm-connection-editor) echo "network-manager-gnome" ;;
	# Arch / pacman
	arch:wl-copy) echo "wl-clipboard" ;;
	arch:wpctl) echo "wireplumber" ;;
	arch:nm-applet) echo "network-manager-applet" ;;
	arch:nm-connection-editor) echo "nm-connection-editor" ;;
	# openSUSE / zypper
	opensuse:wl-copy) echo "wl-clipboard" ;;
	opensuse:wpctl) echo "wireplumber" ;;
	opensuse:nm-applet) echo "NetworkManager-applet" ;;
	opensuse:nm-connection-editor) echo "NetworkManager-connection-editor" ;;
	# dnf distros: nm-applet ships in the nm-connection-editor package —
	# "NetworkManager-applet" is not a real binary name
	centos:wl-copy | fedora:wl-copy) echo "wl-clipboard" ;;
	centos:wpctl | fedora:wpctl) echo "wireplumber" ;;
	centos:nm-applet | fedora:nm-applet) echo "nm-connection-editor" ;;
	*)
		default_pkg_name "$bin"
		;;
	esac
}

# ──────────────────────── required install ────────────────────────
# Upstream re-probes EVERY binary after the batch install (one "installed" /
# "still missing" line each) instead of re-printing the whole section, and
# keeps a single failure verdict — hence this override of the shared step.
install_missing_required() {
	${INSTALL_MODE:-false} || return 0
	[ ${#MISSING_REQUIRED[@]} -gt 0 ] || return 0
	echo -e "${YELLOW}Installing: ${MISSING_REQUIRED[*]}...${NC}"
	local pkgs=() b
	for b in "${MISSING_REQUIRED[@]}"; do pkgs+=("$(pkg_name "$b")"); done
	if install_pkg "${pkgs[@]}"; then
		MISSING_REQUIRED=()
		REQUIRED_FAILURES=0 # verdict is recomputed from the re-probe below
		for b in "${REQUIRED_BINS[@]}" "${REQUIRED_EXT_BINS[@]}"; do
			if bin_req_ok "$b"; then
				ok "$(dep_name "$b") installed"
			else
				MISSING_REQUIRED+=("$b")
				fail "$(dep_name "$b") still missing"
				REQUIRED_FAILURES=$((REQUIRED_FAILURES + 1))
			fi
		done
		if [ ${#MISSING_REQUIRED[@]} -eq 0 ]; then
			echo -e "${GREEN}All required tools now available.${NC}"
		else
			echo -e "${RED}Not in system repos — install manually: wezterm (https://wezterm.org/installation), hyprlock (https://github.com/hyprwm/hyprlock), xdg-desktop-portal-hyprland, hyprpolkitagent, hyprpaper, hypridle (on Arch all of these are in the official repo)${NC}"
		fi
	else
		echo -e "${RED}Install command failed. Run: $(get_install_hint "${pkgs[*]}")${NC}"
	fi
	echo ""
}

# ──────────────────────── recommended ────────────────────────
RECOMMENDED_NOTE="(Missing won't block monkey-hyprland, but will degrade tray / lock / brightness / gui-dialog experience)"
RECOMMENDED_CHECKS=(
	"nm-applet|bin|nm-applet (tray network manager)"
	"hyprlock|bin|hyprlock (lock screen)"
	"brightnessctl|bin|brightnessctl"
	"pavucontrol|bin|pavucontrol"
	"nm-connection-editor|bin|nm-connection-editor"
	"hyprpicker|bin|hyprpicker (color picker)"
	"hyprsunset|bin|hyprsunset (color temperature)"
	"hyprland-dialog|bin|hyprland-guiutils (GUI helper dialogs/run/welcome)"
)

# ──────────────────────── advisory ────────────────────────
# hypr-rdp is reported here, never installed by this script: no repo carries
# it, and the installer builds it from source (install_step_post_tool). An
# RECOMMENDED_CHECKS entry would need install=none — and checks.sh prints a
# red "✗ failed to install" for those — so an advisory section is the honest
# fit. The credentials file matters as much as the binary: hyprland.lua's RDP
# section refuses to start the server without it.
# title|note|type|params|ok|incomplete|missing — the missing text carries its
# own second line (the nerd-fonts URL).
ADVISORY_SECTIONS=(
	"Fonts (optional)|(waybar icons use Nerd Font glyphs)|nerdfont||Nerd Font found||No Nerd Font detected — waybar icons may render as boxes\n    https://github.com/ryanoasis/nerd-fonts"
	"RDP server (optional)|(remote desktop on port 3389)|cmd|hypr-rdp|hypr-rdp available||hypr-rdp not installed — install.sh builds it from source\n    https://github.com/MuNeNICK/hypr-rdp#build-from-source"
	"RDP config template (optional)|(hyprland.lua renders config.toml from it)|path|$HOME/.config/hypr/rdp/config.toml.in|template present||hypr-rdp will not start until the template exists"
	"RDP credentials (optional)|(hypr-rdp will not start without it)|path|$HOME/.config/hypr-rdp/credentials|credentials present||no password file — hypr-rdp will not start until one exists\n    run install.sh, which generates one"
)

# ──────────────────────── config ────────────────────────
# hyprland's config check is its own: the whole repo is linked as
# ~/.config/hypr, waybar/wlogout are separate. Overrides the shared
# check_config_files after sourcing.
check_config_files() {
	# --skip-check-config (passed by install.sh): the config symlinks are
	# linked AFTER this script runs, so judging them here would fail every
	# chained run and burn all three retries. Standalone runs (the manual
	# diagnosis entry point) still get the full check.
	if $SKIP_CONFIG_CHECKS; then
		warn "config checks skipped (handled by the installer)"
		return 0
	fi
	echo -e "${BOLD}Config files${NC}"
	local script_dir
	script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

	# The whole repo is expected to be linked as ~/.config/hypr (single dir
	# link covers hyprland.lua, hypr*.conf and pictures/). waybar/wlogout
	# are checked separately below.
	local hypr_dir="${HOME}/.config/hypr"
	if [[ -L "$hypr_dir" ]]; then
		local target
		target=$(readlink -f "$hypr_dir" 2>/dev/null || readlink "$hypr_dir")
		if [[ "$target" == "$script_dir" ]]; then
			ok "~/.config/hypr → ${target}"
		else
			warn "~/.config/hypr → ${target} (not this repo: ${script_dir})"
		fi
	elif [[ -d "$hypr_dir" ]]; then
		warn "~/.config/hypr is a plain directory (old per-file links) — re-link: ln -sfn ${script_dir} ${hypr_dir}"
	else
		fail "~/.config/hypr not found (run: ln -sfn ${script_dir} ~/.config/hypr)"
		REQUIRED_FAILURES=$((REQUIRED_FAILURES + 1))
	fi

	local waybar_dir="${HOME}/.config/waybar"
	if [[ -L "$waybar_dir" ]]; then
		local target
		target=$(readlink -f "$waybar_dir" 2>/dev/null || readlink "$waybar_dir")
		ok "waybar → ${target}"
	elif [[ -f "$waybar_dir/config.jsonc" && -f "$waybar_dir/style.css" ]]; then
		if [[ -f "${script_dir}/waybar/config.jsonc" && "$waybar_dir/config.jsonc" -ef "${script_dir}/waybar/config.jsonc" ]]; then
			ok "waybar → ${script_dir}/waybar"
		else
			warn "waybar is a plain directory (not a symlink to ${script_dir}/waybar)"
		fi
	else
		fail "waybar config not found (run: ln -sfn ${script_dir}/waybar ~/.config/waybar)"
		REQUIRED_FAILURES=$((REQUIRED_FAILURES + 1))
	fi

	if [[ -d "${HOME}/.config/wlogout" ]] || have_native_cmd wlogout; then
		ok "wlogout present (power menu)"
	else
		warn "wlogout config dir not found (waybar power button needs it)"
	fi
	echo ""
}

checkhealth_main "$@"

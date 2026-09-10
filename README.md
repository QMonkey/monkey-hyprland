# monkey-hyprland

## Introduction

The project monkey-hyprland, aims to make a clean, fast and vim-flavored Hyprland desktop configuration.

**Features:**

| Feature             | Description                                                                         |
| ------------------- | ----------------------------------------------------------------------------------- |
| Lua config          | Written in pure Lua against Hyprland's native `hl` API — no hyprlang fragments      |
| Sonokai theme       | Colors matched to the sonokai dark scheme (same palette as monkey-vim)              |
| Vim-style bindings  | Focus / move / resize windows with `Super + Ctrl/Shift + h/j/k/l`                   |
| Auto monitor detect | Monitors are auto-detected with `highrr` mode and auto scale/position               |
| Laptop aware        | Touchpad gestures and brightness keys are enabled automatically on battery machines |
| Minimal animations  | Animations disabled for performance; subtle blur and shadows kept                   |
| waybar status bar   | Paired waybar config (workspaces, clock, tray, network, audio, battery, power menu) |

## Requirements

- Hyprland **0.55.0+** (native Lua config support with the `hl` API landed in 0.55.0; the bundled build with Lua support can be verified with `Hyprland --version | grep -i lua`)
- waybar
- A Wayland session (this config is Wayland-only; no X11 fallback)

> If your distro's packaged Hyprland is older than 0.55.0, build it from source following the official wiki's [Manual build](https://wiki.hyprland.org/Getting-Started/Installation/#manual-build) section. Note the C++26 toolchain requirement (**gcc >= 16** or **clang >= 19**); always update via `git pull` + `git submodule update --init --recursive` + rebuild so the hypr* dependencies stay in sync with Hyprland.

## Installation

### 1. Install dependencies

#### Common tools

| Tool                                        | Purpose                                                                   | Required |
| ------------------------------------------- | ------------------------------------------------------------------------- | -------- |
| Hyprland                                    | The compositor (must support the Lua `hl` config API)                     | Yes      |
| [waybar](https://github.com/Alexays/Waybar) | Status bar (workspaces, tray, network, audio, battery)                    | Yes      |
| wezterm                                     | Default terminal emulator (`Super + Enter`)                               | Yes      |
| wofi                                        | Application launcher (`Super + d`)                                        | Yes      |
| grim + slurp                                | Screenshot region selection (`Super+,`) and full screen (`Super+Shift+,`) | Yes      |
| wl-clipboard (`wl-copy`)                    | Screenshots are piped to the clipboard                                    | Yes      |
| wlogout                                     | Power menu (waybar power button)                                          | Yes      |
| wireplumber (`wpctl`)                       | Volume / mute keys and the waybar audio module                            | Yes      |

#### Recommended tools

| Tool                 | Purpose                                                 | Required    |
| -------------------- | ------------------------------------------------------- | ----------- |
| nm-applet            | Tray network manager applet (auto-started when present) | Recommended |
| hyprlock             | Screen locker (`Super + Escape`)                        | Recommended |
| brightnessctl        | Brightness keys (laptops only, auto-detected)           | Recommended |
| pavucontrol          | Audio mixer (waybar pulseaudio click)                   | Recommended |
| nm-connection-editor | Network settings (waybar network click)                 | Recommended |
| gnome-calendar       | Calendar (waybar clock right-click)                     | Optional    |

```bash
# Debian
sudo apt-get install hyprland waybar wofi grim slurp wl-clipboard wlogout wireplumber \
    network-manager-gnome brightnessctl pavucontrol nm-connection-editor gnome-calendar
# wezterm: https://wezterm.org/installation
# hyprlock: https://github.com/hyprwm/hyprlock (not in older apt repos)

# OpenSUSE
sudo zypper install hyprland waybar wofi grim slurp wl-clipboard wlogout wireplumber \
    NetworkManager-applet brightnessctl pavucontrol nm-connection-editor gnome-calendar

# Arch Linux
sudo pacman -S hyprland waybar wezterm wofi grim slurp wl-clipboard wlogout wireplumber \
    network-manager-applet hyprlock brightnessctl pavucontrol nm-connection-editor gnome-calendar

# CentOS/RHEL — hyprland is not packaged in any repo; build it from source
# (see Requirements). The remaining tools:
sudo dnf install waybar grim slurp wl-clipboard wireplumber brightnessctl pavucontrol
# wezterm: https://wezterm.org/installation
# wofi, wlogout, hyprlock: build from source or via brew/nix
```

#### Fonts (optional)

waybar uses Nerd Font glyphs (workspaces, network, battery, power icons). Install a [Nerd Font](https://github.com/ryanoasis/nerd-fonts) monospace font and select it in `waybar/style.css`.

### 2. Health check

Verify that all required dependencies and the config symlinks are available:

```bash
./checkhealth.sh
```

Pass `--install` to automatically install missing dependencies. Supports apt/zypper/dnf/pacman:

```bash
./checkhealth.sh --install
```

### 3. Install monkey-hyprland

```bash
cd monkey-hyprland
ln -sf $(pwd)/hyprland.lua ~/.config/hypr/hyprland.lua
ln -sf $(pwd)/waybar ~/.config/waybar
```

Then start (or restart) Hyprland. waybar and nm-applet are launched automatically on startup.

### 4. Start Hyprland

#### From a TTY (manual)

Log in on a TTY (Ctrl+Alt+F1~F6), make sure you are not root, and run:

```bash
Hyprland
```

Never run it under `sudo`/`root`. If the session ends (Super+Shift+e), you are dropped back to the TTY.

#### Auto-start on boot

Add the following to your shell rc file (`~/.zshrc` or `~/.bashrc`):

```bash
# Start Hyprland on tty1 login only, and only outside of an existing session
if [ -z "$WAYLAND_DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
    exec Hyprland
fi
```

- `XDG_VTNR=1` limits auto-start to tty1; log in on tty2 to get a plain shell.
- `exec` replaces the shell with Hyprland so logging out of Hyprland returns you to the login prompt.

Restart, log in on tty1, and Hyprland starts automatically.

> [uwsm](https://github.com/Vladimir-csp/uwsm) is a more thorough alternative (proper systemd session units, better cleanup). If installed, replace `exec Hyprland` with `exec uwsm start -- Hyprland`.

### 5. Update project

```bash
cd monkey-hyprland
git pull
```

Reload the config with `hyprctl reload` (or restart Hyprland) and `pkill waybar; waybar &` for waybar changes.

## Keybindings

```text
The "Super" key below means the Windows/Command key.
```

### 1. Window management

#### 1.1 Focus / Move / Resize (vim-style)

```text
Super+h / Super+j / Super+k / Super+l     Focus left / down / up / right
Super+Ctrl+h/j/k/l                        Move window left / down / up / right
Super+Shift+h/j/k/l                       Resize window left / down / up / right
```

Arrow key alternatives exist for all of the above (`Super`, `Super+Ctrl`, `Super+Shift` + arrow keys).

#### 1.2 Actions

```text
Super+c        Close window
Super+v        Toggle floating
Super+p        Pseudo-tiling
Super+t        Toggle split
Super+f        Fullscreen
Super+Ctrl+p   Pin window (keep on all workspaces)
```

#### 1.3 Mouse

```text
Super+left button     Drag window
Super+right button    Resize window
Super+scroll          Switch workspace (down = next, up = previous)
```

### 2. Workspaces

```text
Super+1~9             Switch to workspace 1~9
Super+Shift+1~9       Move active window to workspace 1~9
Super+S               Toggle special workspace "magic" (scratchpad)
Super+Shift+S         Move active window to special workspace "magic"
Super+[               Focus previous monitor
Super+]               Focus next monitor
Super+Shift+[         Move window to previous monitor
Super+Shift+]         Move window to next monitor
```

### 3. Applications & system

```text
Super+Return          Terminal (wezterm)
Super+d               Application launcher (wofi drun)
Super+Escape          Lock screen (hyprlock, if installed)
Super+Shift+e         Exit Hyprland
```

### 4. Media & brightness keys

```text
XF86AudioRaiseVolume   Volume up 5% (capped at 100%)
XF86AudioLowerVolume   Volume down 5%
XF86AudioMute          Toggle sink mute
XF86AudioMicMute       Toggle microphone mute
XF86MonBrightnessUp    Brightness up 5%      (laptop only)
XF86MonBrightnessDown  Brightness down 5%    (laptop only)
```

### 5. Screenshots

```text
Super+,          Select a region with slurp, screenshot with grim, copy to clipboard
Super+Shift+,    Screenshot the full screen, copy to clipboard
```

## Window rules

- Maximize events are suppressed for all windows (avoids layout bugs)
- XWayland windows with empty class/title are not focused (fixes drag issues)
- Small utility apps (calculator, pavucontrol, settings dialogs, etc.) open floating and centered — see the `float_tools` list in `hyprland.lua`
- Firefox/Chrome `Picture-in-Picture` windows float, pin and stay on top
- Terminals (Alacritty/kitty/wezterm/foot/ghostty) get `0.95` inactive opacity
- waybar gets blur via a layer rule

## Laptop extras

The config detects laptops by checking `/sys/class/power_supply/` for a battery:

- 3-finger horizontal swipe switches workspaces
- `XF86MonBrightness*` keys control brightness via `brightnessctl`

No manual setup is needed — plug in a desktop and the gestures/brightness keys simply don't bind.

## waybar

The bundled `waybar/` directory contains a matching config and style:

```text
modules-left:    hyprland/workspaces  (click to activate, scroll to switch)
modules-center:  clock                (click for full date, right-click gnome-calendar)
modules-right:   tray, network, pulseaudio, battery, custom/power
```

- `custom/power` opens [wlogout](https://github.com/ArtsyMacaw/wlogout)
- Battery has warning (30%) / critical (15%) states; hidden on desktops without a battery
- The style uses the same sonokai palette as `hyprland.lua`

## Precautions

- **Lua config requires Hyprland 0.55.0+** — this config uses the native `hl` Lua API, introduced in 0.55.0. On older builds the Lua file will not load; build from source (see the note in Requirements).
- **Terminal is wezterm** — change the `terminal` variable at the top of `hyprland.lua` to switch (any of `Alacritty|kitty|wezterm|foot|ghostty` also picks up the opacity window rule).
- **Animations are disabled** by design for performance; enable them in the `animations` section if you prefer.

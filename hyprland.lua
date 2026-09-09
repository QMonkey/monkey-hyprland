-- =============================================================================
-- Hyprland Lua Configuration
-- Sonokai Dark Theme | Vim-style Keybindings | Auto Monitor Detection
-- =============================================================================

-- Sonokai Default Style Colors
local colors = {
  black     = '#181819',
  bg_dim    = '#222327',
  bg0       = '#2c2e34',
  bg1       = '#33353f',
  bg2       = '#363944',
  bg3       = '#3b3e48',
  bg4       = '#414550',
  bg_red    = '#55393d',
  bg_yellow = '#4e432f',
  bg_green  = '#394634',
  bg_blue   = '#354157',
  bg_purple = '#434055',
  fg        = '#e2e2e3',
  red       = '#fc5d7c',
  orange    = '#f39660',
  yellow    = '#e7c664',
  green     = '#9ed072',
  blue      = '#76cce0',
  purple    = '#b39df3',
  grey      = '#7f8490',
  grey_dim  = '#595f6f',
}

-- Detect if running on laptop (has battery)
local function is_laptop()
  local handle = io.popen("ls /sys/class/power_supply/ 2>/dev/null | grep -i bat")
  if handle then
    local result = handle:read("*a")
    handle:close()
    return result ~= ""
  end
  return false
end

local laptop = is_laptop()

-- Programs
local terminal = "wezterm"
local menu = "wofi --show drun"

-- =============================================================================
-- MONITORS
-- Auto-detect monitors, use high refresh rate
-- =============================================================================
hl.monitor({
  output   = "",
  mode     = "highrr",
  position = "auto",
  scale    = "auto",
})

-- =============================================================================
-- ENVIRONMENT VARIABLES
-- =============================================================================
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("GDK_BACKEND", "wayland,x11")

-- =============================================================================
-- AUTOSTART
-- =============================================================================
hl.on("hyprland.start", function()
  hl.exec_cmd("waybar &")
  -- Only start nm-applet if network manager is available
  hl.exec_cmd("pgrep -x nm-applet || nm-applet &")
end)

-- =============================================================================
-- GENERAL
-- =============================================================================
hl.config({
  general = {
    gaps_in          = 3,
    gaps_out         = 6,
    border_size      = 2,
    col              = {
      active_border   = { colors = { colors.blue, colors.purple }, angle = 45 },
      inactive_border = colors.grey_dim,
    },
    resize_on_border = true,
    allow_tearing    = false,
    layout           = "dwindle",
  },
})

-- =============================================================================
-- DECORATION
-- =============================================================================
hl.config({
  decoration = {
    rounding         = 6,
    rounding_power   = 2,
    active_opacity   = 1.0,
    inactive_opacity = 0.95,

    shadow           = {
      enabled      = true,
      range        = 4,
      render_power = 3,
      color        = "0x66000000",
    },

    blur             = {
      enabled  = true,
      size     = 3,
      passes   = 1,
      vibrancy = 0.1696,
    },
  },
})

-- =============================================================================
-- ANIMATIONS (Minimal for performance)
-- =============================================================================
hl.config({
  animations = {
    enabled = false,
  },
})

-- =============================================================================
-- INPUT
-- =============================================================================
hl.config({
  input = {
    kb_layout     = "us",
    follow_mouse  = 1,
    sensitivity   = 0,
    accel_profile = "adaptive",
    touchpad      = {
      natural_scroll = true,
    },
  },
})

-- =============================================================================
-- LAYOUTS
-- =============================================================================
hl.config({
  dwindle = {
    preserve_split = true,
    smart_split    = false,
    smart_resizing = true,
  },
  master = {
    new_status = "master",
  },
})

-- =============================================================================
-- MISC
-- =============================================================================
hl.config({
  misc = {
    force_default_wallpaper     = 0,
    disable_hyprland_logo       = true,
    disable_splash_rendering    = true,
    mouse_move_enables_dpms     = true,
    key_press_enables_dpms      = true,
    save_window_size            = true,
    allow_parent_footer_closing = false,
  },
})

-- =============================================================================
-- GESTURES (for touchpad laptops)
-- =============================================================================
if laptop then
  hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
  })
end

-- =============================================================================
-- KEYBINDINGS
-- =============================================================================
local mainMod = "SUPER"

-- Window Focus (Vim-style navigation)
hl.bind(mainMod .. " + h", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + j", hl.dsp.focus({ direction = "down" }))
hl.bind(mainMod .. " + k", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + l", hl.dsp.focus({ direction = "right" }))

-- Move Windows (Super+Ctrl+HJKL)
hl.bind(mainMod .. " + CTRL + h", hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + CTRL + j", hl.dsp.window.move({ direction = "down" }))
hl.bind(mainMod .. " + CTRL + k", hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + CTRL + l", hl.dsp.window.move({ direction = "right" }))

-- Resize Windows (Super+Shift+HJKL)
hl.bind(mainMod .. " + SHIFT + h", hl.dsp.window.resize({ direction = "left" }))
hl.bind(mainMod .. " + SHIFT + j", hl.dsp.window.resize({ direction = "down" }))
hl.bind(mainMod .. " + SHIFT + k", hl.dsp.window.resize({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + l", hl.dsp.window.resize({ direction = "right" }))

-- Arrow key alternatives for window focus
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

-- Arrow key alternatives for moving windows
hl.bind(mainMod .. " + CTRL + left", hl.dsp.window.move({ direction = "left" }))
hl.bind(mainMod .. " + CTRL + right", hl.dsp.window.move({ direction = "right" }))
hl.bind(mainMod .. " + CTRL + up", hl.dsp.window.move({ direction = "up" }))
hl.bind(mainMod .. " + CTRL + down", hl.dsp.window.move({ direction = "down" }))

-- Arrow key alternatives for resizing windows
hl.bind(mainMod .. " + SHIFT + left", hl.dsp.window.resize({ direction = "left" }))
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.resize({ direction = "right" }))
hl.bind(mainMod .. " + SHIFT + up", hl.dsp.window.resize({ direction = "up" }))
hl.bind(mainMod .. " + SHIFT + down", hl.dsp.window.resize({ direction = "down" }))

-- Workspaces (Super + 1-9)
for i = 1, 9 do
  local key = i % 10
  hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
  hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
end

-- Scroll through workspaces
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Special workspace (scratchpad)
hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Applications
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
hl.bind(mainMod .. " + d", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + c", hl.dsp.window.close())
hl.bind(mainMod .. " + v", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mainMod .. " + p", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + j", hl.dsp.layout("togglesplit"))

-- Fullscreen
hl.bind(mainMod .. " + f", hl.dsp.window.fullscreen())

-- Pin window
hl.bind(mainMod .. " + Ctrl + p", hl.dsp.window.pin())

-- Move active window to next/prev monitor
hl.bind(mainMod .. " + bracketleft", hl.dsp.focus({ monitor = "e-1" }))
hl.bind(mainMod .. " + bracketright", hl.dsp.focus({ monitor = "e+1" }))
hl.bind(mainMod .. " + SHIFT + bracketleft", hl.dsp.window.move({ monitor = "e-1" }))
hl.bind(mainMod .. " + SHIFT + bracketright", hl.dsp.window.move({ monitor = "e+1" }))

-- Mouse bindings
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Exit
hl.bind(mainMod .. " + SHIFT + e", hl.dsp.exit())

-- Lock screen (if hyprlock is installed)
hl.bind(mainMod .. " + Escape", hl.dsp.exec_cmd("pidof hyprlock || hyprlock"))

-- Laptop multimedia keys
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"),
  { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),
  { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),
  { locked = true, repeating = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),
  { locked = true, repeating = true })

-- Brightness control (laptop only)
if laptop then
  hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"), { locked = true, repeating = true })
  hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"), { locked = true, repeating = true })
end

-- Screenshot
hl.bind(",", hl.dsp.exec_cmd("grim -g \"$(slurp)\" - | wl-copy"), { locked = true })
hl.bind("SHIFT + ,", hl.dsp.exec_cmd("grim - | wl-copy"), { locked = true })

-- =============================================================================
-- WINDOW RULES
-- =============================================================================

-- Suppress maximize events (prevents bugs)
hl.window_rule({
  name           = "suppress-maximize",
  match          = { class = ".*" },
  suppress_event = "maximize",
})

-- Fix XWayland dragging issues
hl.window_rule({
  name     = "fix-xwayland-drags",
  match    = {
    class      = "^$",
    title      = "^$",
    xwayland   = true,
    float      = true,
    fullscreen = false,
    pin        = false,
  },
  no_focus = true,
})

-- Float rules for small tools
local float_tools = {
  "Calculator",
  "gnome-calendar",
  "pavucontrol",
  "nm-connection-editor",
  "blueman-manager",
  "file-roller",
  "ark",
  "gnome-font-viewer",
  "arandr",
  "veracrypt",
  "fileprogress",
  "gcr-prompter",
  "gnome-shell",
  "kleo",
  "nm-connection-editor",
  "org.gnome.Settings",
  "org.gnome.tweaks",
  "pwvucontrol",
  "qalculate-gtk",
  "qt5ct",
  "qt6ct",
  "slack",
  "solaar",
  "thunar",
  "xdg-desktop-portal-gtk",
  "xdg-desktop-portal-hyprland",
  "zenity",
}

for _, class in ipairs(float_tools) do
  hl.window_rule({
    name   = "float-" .. class,
    match  = { class = class },
    float  = true,
    center = true,
  })
end

-- Float for specific titles
hl.window_rule({
  name   = "float-picture-in-picture",
  match  = { title = "Picture-in-Picture" },
  float  = true,
  pin    = true,
  on_top = true,
})

hl.window_rule({
  name   = "float-file-progress",
  match  = { title = "File Operation Progress" },
  float  = true,
  center = true,
})

-- Opacity rules for specific apps
hl.window_rule({
  name             = "opacity-terminal",
  match            = { class = "^(Alacritty|kitty|wezterm|foot|ghostty)$" },
  active_opacity   = 1.0,
  inactive_opacity = 0.95,
})

-- Layer rules for waybar
hl.layer_rule({
  name  = "waybar",
  match = { namespace = "waybar" },
  blur  = true,
})

-- =============================================================================
-- END OF CONFIG
-- =============================================================================

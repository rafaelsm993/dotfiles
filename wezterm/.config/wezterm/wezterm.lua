local wezterm = require 'wezterm'
local act = wezterm.action

-- ── Transparency toggle ────────────────────────────────────────────────────
-- Toggles window_background_opacity between transparent (0.85) and opaque (1.0).
-- Neovim inherits automatically via `Normal bg = none`.
-- Trigger with CTRL+SHIFT+O.
local OPACITY_ON = 0.85
local OPACITY_OFF = 1.0

wezterm.on('toggle-transparency', function(window)
  local overrides = window:get_config_overrides() or {}
  if (overrides.window_background_opacity or OPACITY_ON) >= OPACITY_OFF then
    overrides.window_background_opacity = OPACITY_ON
  else
    overrides.window_background_opacity = OPACITY_OFF
  end
  window:set_config_overrides(overrides)
end)

-- ── Status bar: show LEADER / key-table mode ───────────────────────────────
wezterm.on('update-status', function(window, _)
  local stat = ''
  if window:leader_is_active() then
    stat = ' LDR '
  elseif window:active_key_table() then
    stat = ' ' .. window:active_key_table():upper() .. ' '
  end
  window:set_left_status(wezterm.format {
    { Attribute = { Intensity = 'Bold' } },
    { Foreground = { Color = '#7aa2f7' } },
    { Text = stat },
  })
end)

-- ── Config ─────────────────────────────────────────────────────────────────
local config = wezterm.config_builder()

config.automatically_reload_config = true
config.enable_tab_bar = true
config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = true
config.window_close_confirmation = 'NeverPrompt'
config.window_decorations = 'RESIZE'
config.font = wezterm.font 'JetBrains Mono'
config.font_size = 14
config.line_height = 1.2
config.cursor_blink_rate = 0
config.hide_tab_bar_if_only_one_tab = true
config.window_padding = { left = 0, right = 0, top = 0, bottom = 0 }
config.window_background_opacity = OPACITY_ON
config.color_scheme = 'Tokyo Night'
-- config.color_scheme = 'Tokyo Night Light (Gogh)'
config.max_fps = 180
config.prefer_egl = true
config.enable_wayland = false;

-- Windows host: open straight into the Arch WSL distro, where herdr runs.
if wezterm.target_triple:find('windows') then
  config.default_prog = { 'wsl.exe', '-d', 'archlinux', '--cd', '~' }
end

-- DEBUG: press CTRL+SHIFT+L in wezterm to open the overlay
-- config.debug_key_events = true

-- Disable defaults to prevent silent conflicts with the custom layout below
config.disable_default_key_bindings = true

-- Herdr is the multiplexer: WezTerm must not claim CTRL+Space or any
-- leader chord, or Herdr never sees the prefix. Only direct CTRL+SHIFT
-- chords remain here.
config.keys = {
  { key = 'c', mods = 'CTRL|SHIFT', action = act.CopyTo 'Clipboard' },
  { key = 'v', mods = 'CTRL|SHIFT', action = act.PasteFrom 'Clipboard' },
  { key = 'l', mods = 'CTRL|SHIFT', action = act.ShowDebugOverlay },
  -- Toggle terminal + Neovim transparency (Hyprland blur effect). Was <leader>o.
  { key = 'o', mods = 'CTRL|SHIFT', action = act.EmitEvent 'toggle-transparency' },
}

return config

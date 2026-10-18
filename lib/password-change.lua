-- The change-password screen (lib/sddm-session): one full-screen terminal, no shortcuts, no way to the desktop.
-- It exits when the form does, whatever the outcome.

-- Same keyboard layout as Omarchy's desktop (and its disk unlock), so the password is typed as on the login screen.
local xkb = {}
local vconsole = io.open("/etc/vconsole.conf", "r")
if vconsole then
  for line in vconsole:lines() do
    local key, value = line:match("^%s*(XKB%w+)%s*=%s*\"?([^\"#%s]*)")
    if key then xkb[key] = value end
  end
  vconsole:close()
end

hl.config({
  input = { kb_layout = xkb.XKBLAYOUT or "us", kb_variant = xkb.XKBVARIANT or "", numlock_by_default = true },
  general = { gaps_in = 0, gaps_out = 0, border_size = 0 },
  misc = { disable_hyprland_logo = true, disable_splash_rendering = true, force_default_wallpaper = 0 },
  animations = { enabled = false },
  -- Hyprland's own popups (news after an update) would take the keyboard from the password prompt
  ecosystem = { no_update_news = true, no_donation_nag = true },
})
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

-- foot with none of the person's own config, and without its shortcuts that start programs (Ctrl+Shift+N opens a
-- shell), so the form is the only way out.
local FOOT = "foot --config=/dev/null -o key-bindings.spawn-terminal=none -o key-bindings.show-urls-launch=none "

hl.on("hyprland.start", function()
  hl.exec_cmd(FOOT .. os.getenv("OI_FORM") .. "; hyprctl dispatch 'hl.dsp.exit()'")
end)

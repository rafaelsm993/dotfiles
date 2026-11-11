# Default browser for CLI tools that honour $BROWSER (gh, xdg-open fallbacks, ...).
# The Hyprland/uwsm session already exports this via ~/.config/uwsm/env; this
# covers the sessions that don't source it: bare TTY logins, ssh, cron.
if not set -q BROWSER
    for browser in vivaldi-stable vivaldi
        if command -q $browser
            set -gx BROWSER $browser
            break
        end
    end
end

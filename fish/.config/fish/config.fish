# CachyOS-specific config (skip on other distros)
if test -f /usr/share/cachyos-fish-config/cachyos-config.fish
    source /usr/share/cachyos-fish-config/cachyos-config.fish
else
    fish_add_path ~/.local/bin ~/bin
end

# overwrite greeting
# potentially disabling fastfetch
#function fish_greeting
#    # smth smth
#end

mise activate fish | source

# Salesforce CLI: WSL has no D-Bus secret service (libsecret/secret-tool fails with
# "The name is not activatable"), so force the CLI's file-based keychain, which
# decrypts auth files with ~/.sfdx/key.json instead of the OS keyring.
set -gx SF_USE_GENERIC_UNIX_KEYCHAIN true
set -gx SFDX_USE_GENERIC_UNIX_KEYCHAIN true
# Salesforce CLI: `sf org login web` binds its OAuth callback server to whatever
# "localhost" resolves to first. Under WSL2 that is IPv6 [::1], which the Windows
# browser cannot reach through localhost-forwarding, so the redirect hangs and the
# auth code is never redeemed -> "invalid_grant: expired authorization code".
# Forcing IPv4 makes it bind 127.0.0.1, which Windows can reach.
set -gx NODE_OPTIONS --dns-result-order=ipv4first
# oh-my-posh init fish --config 'https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/refs/heads/main/themes/easy-term.omp.json' | source
oh-my-posh init fish --config "$__fish_config_dir/tokyo.omp.json" | source

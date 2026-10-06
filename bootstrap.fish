#!/usr/bin/env fish
#
# Bootstrap a fresh WSL Arch Linux install from these dotfiles.
#
#   ./bootstrap.fish [--dry-run] [--force] [--only PHASE] [--skip PHASE]
#
# Every phase is idempotent: re-running is safe and mostly a no-op.
# Nothing here hardcodes a username - the current user is detected at runtime.

set -g REPO_ROOT (realpath (dirname (status filename)))
source $REPO_ROOT/scripts/lib.fish

set -g ONLY_PHASES
set -g SKIP_PHASES

# Stow packages that make sense inside WSL. Excluded on purpose:
#   wezterm  - WezTerm runs on the Windows host, its config lives there
#   hypr     - Wayland compositor, no GUI in WSL
#   noctalia - Wayland shell, no GUI in WSL
set -g STOW_PACKAGES fish nvim fastfetch mise herdr

# Order matters:
#   stow before mise (the mise config arrives via stow)
#   mise before npm  (node provides npm)
#   npm before herdr (the herdr agent skill installs via npx)
set -g PHASES packages wslconf stow mise npm omp herdr shell git verify

function usage
    echo "Usage: ./bootstrap.fish [options]"
    echo
    echo "  --dry-run       print actions without executing them"
    echo "  --force         redo steps that are normally skipped when present"
    echo "  --only PHASE    run only these phases (repeatable)"
    echo "  --skip PHASE    skip these phases (repeatable)"
    echo "  --help          show this message"
    echo
    echo "Phases: $PHASES"
end

# ---------------------------------------------------------------- args ----

set -l i 1
while test $i -le (count $argv)
    switch $argv[$i]
        case --dry-run
            set -g DOTFILES_DRY_RUN 1
        case --force
            set -g DOTFILES_FORCE 1
        case --only
            set i (math $i + 1)
            if test $i -gt (count $argv); log_error "--only needs a phase name"; exit 2; end
            set -a ONLY_PHASES $argv[$i]
        case --skip
            set i (math $i + 1)
            if test $i -gt (count $argv); log_error "--skip needs a phase name"; exit 2; end
            set -a SKIP_PHASES $argv[$i]
        case --help -h
            usage
            exit 0
        case '*'
            log_error "unknown option: $argv[$i]"
            usage
            exit 2
    end
    set i (math $i + 1)
end

for p in $ONLY_PHASES $SKIP_PHASES
    if not contains $p $PHASES
        log_error "unknown phase: $p"
        log_error "valid phases: $PHASES"
        exit 2
    end
end

function should_run --argument-names phase
    if contains $phase $SKIP_PHASES
        return 1
    end
    if test (count $ONLY_PHASES) -gt 0
        contains $phase $ONLY_PHASES
        return $status
    end
    return 0
end

# ----------------------------------------------------------- preflight ----

function preflight
    log_info "Preflight checks"

    if not test -f /etc/arch-release
        log_error "This script targets Arch Linux."
        exit 1
    end
    log_ok "Arch Linux detected"

    if test (id -u) -eq 0
        log_error "Do not run as root. Run as your normal user; sudo is invoked per-step."
        exit 1
    end
    log_ok "running as "(whoami)

    if grep -qi microsoft /proc/version
        log_ok "WSL detected"
    else
        log_warn "not detected as WSL - WSL-specific steps will be skipped"
    end

    if not test -f $REPO_ROOT/.stowrc
        log_error "cannot find .stowrc - is $REPO_ROOT the dotfiles repo root?"
        exit 1
    end
    log_ok "repo root: $REPO_ROOT"

    if test $DOTFILES_DRY_RUN -eq 1
        log_warn "DRY RUN - no changes will be made"
    end
end

# -------------------------------------------------------------- phases ----

function phase_packages
    log_info "Phase: system packages"

    set -l pkgfile $REPO_ROOT/scripts/packages.txt
    set -l pkgs (read_list $pkgfile)
    if test (count $pkgs) -eq 0
        log_error "no packages read from $pkgfile"
        return 1
    end
    log_ok (count $pkgs)" packages declared"

    set -l missing
    for p in $pkgs
        if not pkg_installed $p
            set -a missing $p
        end
    end

    if test (count $missing) -eq 0
        log_skip "all packages already installed"
        return 0
    end

    log_info "installing "(count $missing)" missing: $missing"
    run sudo pacman -Syu --needed --noconfirm $missing
end

function phase_wslconf
    log_info "Phase: /etc/wsl.conf"

    if not grep -qi microsoft /proc/version
        log_skip "not running under WSL"
        return 0
    end

    set -l template $REPO_ROOT/scripts/wsl.conf.template
    if not test -f $template
        log_error "missing $template"
        return 1
    end

    # Render the template for the current user (no hardcoded username).
    set -l rendered (mktemp)
    sed "s/__USER__/"(whoami)"/" $template >$rendered

    if test -f /etc/wsl.conf; and test $DOTFILES_FORCE -eq 0
        if diff -q /etc/wsl.conf $rendered >/dev/null 2>&1
            log_skip "/etc/wsl.conf already matches"
        else
            log_warn "/etc/wsl.conf exists and differs - leaving it alone (use --force to overwrite)"
            diff /etc/wsl.conf $rendered
        end
        rm -f $rendered
        return 0
    end

    run sudo install -m 0644 $rendered /etc/wsl.conf
    rm -f $rendered
    log_warn "wsl.conf changed - run 'wsl --shutdown' from Windows for it to take effect"
end

function phase_stow
    log_info "Phase: stow symlinks"

    if not have stow
        log_error "stow not installed - run the packages phase first"
        return 1
    end

    # .stowrc holds machine-specific absolute paths, so pass ours explicitly.
    for pkg in $STOW_PACKAGES
        if not test -d $REPO_ROOT/$pkg
            log_warn "no such stow package: $pkg"
            continue
        end

        # A pre-existing real file/dir (not a symlink into this repo) blocks
        # stow. On a fresh install this is common: a tool writes its own
        # config before we ever stow it. Back it up rather than fail or
        # silently clobber it.
        if not stow -n --restow --target=$HOME --dir=$REPO_ROOT $pkg >/dev/null 2>&1
            set -l conflict $HOME/.config/$pkg
            if test -e $conflict; and not test -L $conflict
                set -l backup $conflict.pre-stow.(date +%Y%m%d%H%M%S)
                log_warn "$conflict exists and is not a symlink - backing up to $backup"
                run mv $conflict $backup
            end
        end

        # --no-folding: link files, not whole dirs, so runtime state
        # (herdr sessions/logs, fish_variables churn) never lands in the repo.
        if run stow --no-folding --restow --target=$HOME --dir=$REPO_ROOT $pkg
            log_ok "stowed $pkg"
        else
            log_error "stow failed for $pkg"
        end
    end

    log_skip "not stowed (host/GUI only): wezterm hypr noctalia"
end

function phase_mise
    log_info "Phase: mise runtimes"

    if not have mise
        log_error "mise not installed - run the packages phase first"
        return 1
    end

    if not test -f $HOME/.config/mise/config.toml
        log_error "no ~/.config/mise/config.toml - run the stow phase first"
        return 1
    end

    run mise install
    if test $DOTFILES_DRY_RUN -eq 0
        mise ls
    end
end

function phase_npm
    log_info "Phase: global npm packages"

    # node/npm come from mise; pick them up even if this shell predates it.
    if not have npm
        if have mise
            log_info "npm not on PATH yet - activating mise for this run"
            set -l nodebin (mise where node 2>/dev/null)/bin
            if test -d $nodebin
                set -gx PATH $nodebin $PATH
            end
        end
    end

    if not have npm
        log_error "npm not found - run the mise phase first (node provides npm)"
        return 1
    end

    set -l pkgs (read_list $REPO_ROOT/scripts/npm-globals.txt)
    set -l installed (npm ls -g --depth=0 --parseable 2>/dev/null \
        | string replace -rf '.*/node_modules/' '')

    set -l missing
    for p in $pkgs
        if not contains $p $installed
            set -a missing $p
        end
    end

    if test (count $missing) -eq 0
        log_skip "all npm globals present"
        return 0
    end

    log_info "installing: $missing"
    run npm install -g $missing
end

function phase_omp
    log_info "Phase: oh-my-posh"

    if have oh-my-posh; and test $DOTFILES_FORCE -eq 0
        log_skip "already installed ("(oh-my-posh version 2>/dev/null)")"
        return 0
    end

    run mkdir -p $HOME/.local/bin
    run bash -c 'curl -fsSL https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin"'
end

function phase_herdr
    log_info "Phase: herdr (terminal multiplexer)"

    if have herdr; and test $DOTFILES_FORCE -eq 0
        log_skip "already installed ("(herdr --version 2>/dev/null)")"
    else
        run mkdir -p $HOME/.local/bin
        run sh -c 'curl -fsSL https://herdr.dev/install.sh | sh'
    end

    if test $DOTFILES_DRY_RUN -eq 0; and not have herdr
        fish_add_path -g $HOME/.local/bin
    end

    # Agent integrations: only for agents whose config dir exists.
    for pair in claude:.claude copilot:.copilot codex:.codex
        set -l agent (string split ':' $pair)[1]
        set -l dir (string split ':' $pair)[2]
        if test -d $HOME/$dir
            run herdr integration install $agent
        else
            log_skip "herdr integration $agent (no ~/$dir)"
        end
    end

    if have npx
        run npx -y skills add herdrdev/herdr --skill herdr -g -a claude-code github-copilot -y
    else
        log_warn "npx missing - skipped herdr agent skill (run the mise phase first)"
    end
end

function phase_shell
    log_info "Phase: default shell"

    set -l fishpath (command -v fish)
    if test -z "$fishpath"
        log_error "fish not found"
        return 1
    end

    # On Arch /usr/sbin is a symlink to bin, so `command -v` and the passwd
    # entry can name the same binary by different paths. Compare resolved
    # paths, otherwise this phase would chsh on every single run.
    set -l current (string split ':' (getent passwd (whoami)))[7]
    if test -n "$current"; and test (realpath $current 2>/dev/null) = (realpath $fishpath)
        log_skip "login shell already $current"
        return 0
    end

    # chsh validates against /etc/shells using the literal path.
    if not grep -qx -- $fishpath /etc/shells
        run bash -c "echo $fishpath | sudo tee -a /etc/shells >/dev/null"
    end
    run chsh -s $fishpath
    log_warn "shell change takes effect on next login"
end

function phase_git
    log_info "Phase: git config"

    run git config --global init.defaultBranch main
    run git config --global core.autocrlf input

    set -l name (git config --global user.name)
    set -l email (git config --global user.email)

    if test -n "$name"
        log_ok "user.name = $name"
    else
        log_warn "git user.name unset - set it with: git config --global user.name 'Your Name'"
    end

    if test -n "$email"
        log_ok "user.email = $email"
    else
        log_warn "git user.email unset - set it with: git config --global user.email you@example.com"
    end
end

function phase_verify
    log_info "Phase: verification"
    set -l failures 0

    for c in fish git nvim stow mise node npm sf oh-my-posh fastfetch rg fd yazi lazygit herdr
        if have $c
            log_ok "$c -> "(command -v $c)
        else
            log_error "$c NOT FOUND"
            set failures (math $failures + 1)
        end
    end

    # Packages are stowed with --no-folding, so ~/.config/<pkg> is a real dir
    # of file links. "Fully stowed" = a stow dry run has nothing left to LINK.
    for l in $STOW_PACKAGES
        set -l pending (stow -n -v --no-folding --target=$HOME --dir=$REPO_ROOT $l 2>&1 | string match -r '^LINK: .*')
        if test (count $pending) -eq 0
            log_ok "$l fully stowed"
        else
            log_error "$l has "(count $pending)" unlinked file(s) - run: ./bootstrap.fish --only stow"
            set failures (math $failures + 1)
        end
    end

    if have herdr
        if herdr config check >/dev/null 2>&1
            log_ok "herdr config check passed"
        else
            log_error "herdr config check failed - run: herdr config check"
            set failures (math $failures + 1)
        end
    end

    # WSL has no D-Bus secret service, so the Salesforce CLI must use its
    # file-based keychain or every auth file fails to decrypt.
    if grep -q SF_USE_GENERIC_UNIX_KEYCHAIN $HOME/.config/fish/config.fish 2>/dev/null
        log_ok "SF_USE_GENERIC_UNIX_KEYCHAIN present in fish config"
    else
        log_error "SF_USE_GENERIC_UNIX_KEYCHAIN missing - sf CLI will fail in WSL"
        set failures (math $failures + 1)
    end

    if grep -qi microsoft /proc/version
        if mount | grep -q 'on /mnt/c .*metadata'
            log_ok "/mnt/c mounted with metadata"
        else
            log_warn "/mnt/c lacks 'metadata' - check /etc/wsl.conf, then run 'wsl --shutdown'"
        end
    end

    echo
    if test $failures -eq 0
        log_ok "all checks passed"
        return 0
    else
        log_error "$failures check(s) failed"
        return 1
    end
end

# ---------------------------------------------------------------- main ----

preflight

set -g FAILED_PHASES
for p in $PHASES
    if should_run $p
        if not phase_$p
            log_error "phase '$p' failed"
            set -a FAILED_PHASES $p
        end
    else
        log_skip "phase '$p' (filtered out)"
    end
end

echo
if test (count $FAILED_PHASES) -gt 0
    log_error "Bootstrap finished with failures: $FAILED_PHASES"
else
    log_info "Bootstrap complete."
end

log_warn "Next steps (manual):"
echo "  - Run 'wsl --shutdown' from Windows if /etc/wsl.conf changed"
echo "  - Restart your terminal to pick up the fish login shell"
echo "  - Authenticate Salesforce orgs:  sf org login web --alias DEV"
echo "  - Set your git identity if unset: git config --global user.email you@example.com"

test (count $FAILED_PHASES) -eq 0

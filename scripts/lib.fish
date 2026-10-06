# Shared helpers for dotfiles bootstrap scripts.
# Sourced by bootstrap.fish; not meant to be executed directly.

set -g DOTFILES_DRY_RUN 0
set -g DOTFILES_FORCE 0

function log_info;  set_color cyan;   echo -n "==> ";  set_color normal; echo $argv; end
function log_ok;    set_color green;  echo -n "  ok "; set_color normal; echo $argv; end
function log_skip;  set_color yellow; echo -n "skip "; set_color normal; echo $argv; end
function log_warn;  set_color yellow; echo -n "warn "; set_color normal; echo $argv; end
function log_error; set_color red;    echo -n "FAIL "; set_color normal; echo $argv >&2; end

# Run a command, or just print it under --dry-run.
function run
    if test $DOTFILES_DRY_RUN -eq 1
        set_color brblack
        echo "  would run: $argv"
        set_color normal
        return 0
    end
    $argv
end

function have
    command -q $argv[1]
end

# Read a data file: strip comments and blank lines, trim whitespace.
function read_list --argument-names path
    if not test -f $path
        return 1
    end
    for line in (cat $path)
        set -l trimmed (string trim -- $line)
        if test -z "$trimmed"; continue; end
        if string match -q '#*' -- $trimmed; continue; end
        echo $trimmed
    end
end

# True if a pacman package OR package group is fully installed.
# `pacman -Qq <group>` fails for groups (e.g. base-devel) even when every
# member is installed, so groups need the -Qg membership comparison.
function pkg_installed --argument-names pkg
    if pacman -Qq $pkg >/dev/null 2>&1
        return 0
    end

    # Is it a known group? Compare declared members against installed ones.
    set -l members (pacman -Sqg $pkg 2>/dev/null)
    if test (count $members) -eq 0
        return 1
    end
    for m in $members
        if not pacman -Qq $m >/dev/null 2>&1
            return 1
        end
    end
    return 0
end

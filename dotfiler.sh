#!/bin/sh
#
# Dotfiler - maintain your dotfiles easily
#
# Copyright (c) 2019-2020 Aryel Mota Góis <aryel.gois@gmail.com>
#
# MIT License

set -eu


program=$(basename "$0")
version=0.1.0

DEFAULT_DIR=home


# Documentation
# =============

usage_init="$program init [DIR]"
usage_add="$program add FILE..."
usage_rm="$program rm FILE..."
usage_mount="$program mount [-ft] [DIR] [DEVICE]"
usage_umount="$program umount [-ft] [DIR]"

# Outputs Dotfiler help.
dotfiler_help () {
    cat <<EOF
Dotfiler lets you organize configuration files in a git(1) repository, while
being able to apply them in your system without the overhead of symbolic links
or keeping the repository itself in your \$HOME.

In fact, your home directory is mounted inside the git repo with a hard link.
This way, changes done on any side are automatically available in the other,
and you just have to commit, like in any repository.

If you do not have enough privileges to use mount(8), it is possible to use a
FUSE filesystem, which should be easier for your administrator to enable than
a full set of root permissions. If that is still a problem they can just add
an entry in the fstab to stop your annoying mails.

Usage: $usage_init
  or:  $usage_add
  or:  $usage_rm
  or:  $usage_mount
  or:  $usage_umount
  or:  $program --help
  or:  $program --version

Options:
  -f, --fuse     Use FUSE filesystem with bindfs(1) instead of hard links
                 with mount(8) and umount(8).
  -h, --help     Show the help text and exit.
  -t, --fstab    On mount it adds an entry to the system's fstab,
                 on unmount it removes the entry.
  -v, --version  Show the version information and exit.

Commands:
  init           Creates a git repository and the mount point DIR, which
                 defaults to \`home'. It may use an existing repo and ask if
                 should mount right away.
  add            Adds one or more FILEs to the re-included files in .gitignore
                 and to the git index.
  rm             Removes one or more FILEs from the working tree, the git
                 index and the re-included files in .gitignore.
  mount          Mounts \$HOME or another DEVICE at DIR with a hard link.
  umount         Unmounts the mount point DIR, undoing the hard link.

Report bugs at <https://github.com/aryelgois/dotfiler/issues>.
EOF
}

# Outputs Dotfiler version.
dotfiler_version () {
    cat <<EOF
Dotfiler version $version

Copyright (c) 2019-2020 Aryel Mota Góis <aryel.gois@gmail.com>.

MIT License <https://opensource.org/licenses/MIT>.
This is free software: you are free to change and redistribute it.
There is NO WARRANTY, to the extent permitted by law.
EOF
}

# Outputs a basic README for Dotfiler repositories.
#
# It uses Markdown format.
write_readme () {
    cat <<EOF
# My dotfiles

These are my dotfiles.

You can use it with [Dotfiler].

[dotfiler]: https://github.com/aryelgois/dotfiler
EOF
}


# Helper functions
# ================

# Writes to stderr.
stderr () {
    >&2 echo "$@"
}

# Asks for user input.
#
# Usage: ask Yn|yN|optional|required PROMPT
#
# Yn|yN     Returns 0 for yes or 1 for no. Default option is in uppercase.
# optional  Allows empty input.
# required  Does not allow empty input.
ask () {
    AFTER=

    case $1 in
    Yn) AFTER='[Y/n] ' ;;
    yN) AFTER='[y/N] ' ;;
    optional|required) ;;
    *)
        stderr 'Invalid option for ask().'
        exit 1
        ;;
    esac

    while true; do
        >&2 printf '%s' "$2 $AFTER"
        INPUT=
        read -r INPUT

        case $1 in
        Yn)
            case $INPUT in
            ''|y|Y|yes|Yes) return 0 ;;
            *) return 1 ;;
            esac
            ;;
        yN)
            case $INPUT in
            y|Y|yes|Yes) return 0 ;;
            *) return 1 ;;
            esac
            ;;
        optional)
            break
            ;;
        required)
            [ -z "$INPUT" ] || break
            ;;
        esac
    done

    echo "$INPUT"
}

# Checks if $1 starts with $2.
starts_with () {
    case $1 in
    $2*) return 0 ;;
    esac
    return 1
}

# Checks if effective user is root.
is_root () {
    if [ "$(id -u)" != '0' ]; then
        return 1
    fi
}


# Commands
# ========

# Initializes a Dotfiler repository.
#
# $1 is the target path to a directory that will be a hard link to $HOME.
# If it is empty, $DEFAULT_DIR is used. It must end with a name.
#
# If no git repository relative to target is found, a new one is initialized.
#
# A .gitignore file is created at the repository's root with an entry to
# ignore everything inside the target, because $HOME usually contains a lot
# of files that should not be under version control.
#
# An initial commit is created if the repository does not have any, or a
# descriptive one if the index is clean.
dotfiler_init () {
    if [ $# -gt 1 ]; then
        stderr "Usage: $usage_init"
        exit 1
    fi

    dir=${1:-$DEFAULT_DIR}
    target=$(basename "$dir")

    # The argument must end with a valid file name.
    case $target in
    .|..)
        stderr 'Invalid directory.'
        exit 1
        ;;
    esac

    # If the argument is a path, follow it up to dirname.
    case $dir in
    */*)
        dir=$(dirname "$dir")
        install -d "$dir"
        cd "$dir"
        ;;
    esac

    # If the user is at $HOME or above, ask where to put the repository.
    if starts_with "$HOME" "$(pwd -P)"; then
        dir=$(ask required 'Where do you want to put the repository?')

        # Test user input and create directory if it does not exist.
        if [ -e "$dir" ]; then
            if [ ! -d "$dir" ]; then
                stderr "\`$dir' is not a directory."
                exit 1
            fi
        else
            install -d "$dir"
        fi

        cd "$dir"

        # Block an atempt to enter the $HOME in the previous input.
        if starts_with "$HOME" "$(pwd -P)"; then
            stderr "You can not keep the repository directly or above your \$HOME."
            exit 1
        fi
    fi

    # The target must be a directory.
    if [ -e "$target" ] && [ ! -d "$target" ]; then
        stderr "\`$(pwd)/$target' is not a directory."
        exit 1
    fi

    cwd=$(pwd -P)

    # Check if a git repository already exists.
    git_dir=$(git rev-parse --git-dir 2> /dev/null || true)
    if [ -n "$git_dir" ]; then
        git_dir=$(realpath "$git_dir")

        # Check if $dir is inside .git.
        if [ "$(git rev-parse --is-inside-work-tree)" != 'true' ]; then
            stderr "A git repository was found at \`$git_dir', but you are not inside its work tree."
            exit 1
        fi

        # If it is at $HOME or if the user does not want to use it, ignore it.
        # If it is in the same directory, it will be used.
        if starts_with "$HOME" "$git_dir"; then
            git_dir=
        elif [ "$git_dir" != "$cwd/.git" ]; then
            ask Yn "Use repository at \`$git_dir'?" || git_dir=
        else
            echo "Found git repository at \`$git_dir'."
        fi
    fi

    # Create new git repository and get its root path.
    if [ -z "$git_dir" ]; then
        git init
        repo_root=$cwd
    else
        repo_root=$(dirname "$git_dir")
    fi

    # Check if index is clean.
    if [ -z "$(git status --porcelain --untracked-files=no)" ]; then
        is_clean=true
    else
        echo 'Notice: index is not clean.'
        is_clean=false
    fi

    # Get relative path to target directory from repository.
    if [ "$repo_root" != "$cwd" ]; then
        relative_target=${cwd#$repo_root/}/$target
    else
        relative_target=$target
    fi

    # Create or update .gitignore file.
    gitignore_file=$repo_root/.gitignore
    if [ -e "$gitignore_file" ]; then
        if ! grep -q "^/$relative_target/\*\*" "$gitignore_file"; then
            echo 'Updating .gitignore. . .'
            echo >> "$gitignore_file"
            echo "/$relative_target/**" >> "$gitignore_file"
        else
            stderr "\`$relative_target' is already initialized."
            exit 1
        fi
    else
        echo 'Creating a .gitignore file. . .'
        echo "/$relative_target/**" > "$gitignore_file"
    fi

    # Create README file.
    readme_file=$repo_root/README.md
    if [ ! -e "$readme_file" ]; then
        echo 'Creating a README file. . .'
        write_readme > "$readme_file"
    fi

    # Create the target directory.
    if [ ! -e "$target" ]; then
        echo "Creating \`$target' directory. . ."
        mkdir "$target"
    fi

    # Create commit.
    if $is_clean; then
        git add "$gitignore_file" "$readme_file"
        if [ -z "$(git rev-list -n 1 --all 2> /dev/null)" ]; then
            echo 'Creating an Initial commit. . .'
            git commit -m 'Initial commit'
        else
            echo 'Committing new mount point. . .'
            git commit -m "Add \`$relative_target' mount point"
        fi
    fi

    # Ask if should mount $HOME.
    if ask Yn "Would you like to mount your \$HOME?"; then
        set --

        default_fuse=$(is_root && echo yN || echo Yn)

        if ask "$default_fuse" 'Would you like to use a FUSE filesystem?'; then
            set -- --fuse
        fi

        default_fstab=$(is_root && echo Yn || echo yN)

        if ask "$default_fstab" 'Would you like to add an entry to fstab?'; then
            set -- "$@" --fstab
        fi

        dotfiler_mount "$@" "$target"
    fi
}

# Adds files to the git index.
#
# A .gitignore file at the repository's root ignores all files inside the
# mount point and maintains a list with re-included files. Each directory
# must be re-included before the file.
#
# If an argument is a directory, a glob pattern is added to re-include all
# files inside of it.
dotfiler_add () {
    if [ $# -eq 0 ]; then
        stderr "Usage: $usage_add"
        exit 1
    fi

    status_code=0

    # For each argument..
    while [ $# -gt 0 ]; do
        arg=$1
        shift 1

        # Check if argument exists.
        if [ ! -e "$arg" ]; then
            stderr "\`$arg' does not exist."
            status_code=1
            continue
        fi

        target=$(realpath "$arg")

        dir=$(dirname "$target")

        # Check if a git repository exists.
        git_dir=$(git -C "$dir" rev-parse --git-dir 2> /dev/null || true)
        if [ -z "$git_dir" ]; then
            stderr "Could not find a git repository above \`$arg'."
            status_code=1
            continue
        fi

        # Check if $arg is inside .git.
        if [ "$(git -C "$dir" rev-parse --is-inside-work-tree)" != 'true' ]; then
            stderr "A git repository was found at \`$git_dir', but \`$arg' is not inside its work tree."
            status_code=1
            continue
        fi

        # Check if the repository is at $HOME or above.
        git_dir=$(realpath "$git_dir")
        if starts_with "$HOME" "$git_dir"; then
            stderr "You can not keep the repository directly or above your \$HOME."
            status_code=1
            continue
        fi

        # Get the repository's root path.
        repo_root=$(dirname "$git_dir")

        # Check if repository has a .gitignore file.
        gitignore_file=$repo_root/.gitignore
        if [ ! -f "$gitignore_file" ]; then
            stderr "Could not find a .gitignore file at \'$repo_root'."
            status_code=1
            continue
        fi

        # Get relative path to target from repository.
        relative_target=${target#$repo_root/}

        # Find base directory in .gitignore that contains target.
        base=
        while read -r match; do
            match=${match#/}
            match=${match%/*}

            if starts_with "$relative_target" "$match/"; then
                base=$match
                break
            fi
        done <<EOF
$(grep -o '^/.*/\*\*' "$gitignore_file")
EOF
        if [ -z "$base" ]; then
            stderr "Could not find base directory in \`$gitignore_file' that contains \`$target'."
            status_code=1
            continue
        fi

        # Get relative path to target from base directory.
        relative_target=${relative_target#$base/}

        # Check whether $target is a directory.
        if [ -d "$target" ]; then
            relative_target=$relative_target/\\\*\\\*
        fi

        # Add each path fragment to .gitignore.
        previous=/$base/\\\*\\\*
        entry=!/$base
        while [ -n "$relative_target" ]; do
            case $relative_target in
            */*)
                entry=$entry/${relative_target%%/*}/
                relative_target=${relative_target#*/}
                ;;
            *)
                entry=$entry/$relative_target
                relative_target=
                ;;
            esac

            if ! grep -q "^$entry" "$gitignore_file"; then
                sed "s|^$previous\$|&\n$entry|" "$gitignore_file" > "$gitignore_file.new"
                mv -- "$gitignore_file.new" "$gitignore_file"
            fi

            previous=$entry
            entry=${entry%/}
        done

        # Update git index.
        git -C "$repo_root" add "$gitignore_file" "$target"
    done

    exit $status_code
}

# Removes files from the working tree and index.
#
# It also removes the entries in the .gitignore that re-includes each file,
# but directory entries are kept.
#
# If an argument is a directory, all tracked files inside of it and all
# entries that starts with it are removed.
#
# It can not remove files inside a directory re-included with a glob pattern.
# You will have to add an exclude rule manually.
dotfiler_rm () {
    if [ $# -eq 0 ]; then
        stderr "Usage: $usage_rm"
        exit 1
    fi

    status_code=0

    # For each argument..
    while [ $# -gt 0 ]; do
        arg=$1
        shift 1

        # Check if argument exists.
        if [ ! -e "$arg" ]; then
            stderr "\`$arg' does not exist."
            status_code=1
            continue
        fi

        target=$(realpath "$arg")

        dir=$(dirname "$target")

        # Check if a git repository exists.
        git_dir=$(git -C "$dir" rev-parse --git-dir 2> /dev/null || true)
        if [ -z "$git_dir" ]; then
            stderr "Could not find a git repository above \`$arg'."
            status_code=1
            continue
        fi

        # Check if $arg is inside .git.
        if [ "$(git -C "$dir" rev-parse --is-inside-work-tree)" != 'true' ]; then
            stderr "A git repository was found at \`$git_dir', but \`$arg' is not inside its work tree."
            status_code=1
            continue
        fi

        # Check if the repository is at $HOME or above.
        git_dir=$(realpath "$git_dir")
        if starts_with "$HOME" "$git_dir"; then
            stderr "You can not keep the repository directly or above your \$HOME."
            status_code=1
            continue
        fi

        # Get the repository's root path.
        repo_root=$(dirname "$git_dir")

        # Check if repository has a .gitignore file.
        gitignore_file=$repo_root/.gitignore
        if [ ! -f "$gitignore_file" ]; then
            stderr "Could not find a .gitignore file at \'$repo_root'."
            status_code=1
            continue
        fi

        # Get relative path to target from repository.
        relative_target=${target#$repo_root/}

        # Check whether $target is a directory.
        if [ -d "$target" ]; then
            relative_target=$relative_target/
        fi

        # Remove target.
        entry=!/$relative_target
        if grep -q "^$entry" "$gitignore_file"; then
            # Remove from working tree and index.
            if [ -d "$target" ]; then
                git -C "$repo_root" rm -r "$target"
            else
                git -C "$repo_root" rm "$target"
            fi

            # Remove from .gitignore.
            grep -v "^$entry" "$gitignore_file" > "$gitignore_file.new"
            mv -- "$gitignore_file.new" "$gitignore_file"
            git -C "$repo_root" add "$gitignore_file"
        else
            stderr "\`$relative_target' is not listed in \`$gitignore_file'."
            status_code=1
            continue
        fi
    done

    exit $status_code
}

# Mounts $HOME inside the repository.
#
# The first positional argument is the mount point directory. If it is not
# provided, $DEFAULT_DIR is used. The next argument is the device being
# mounted, which defaults to $HOME.
#
# It requires root privileges, but a FUSE filesystem is supported as well.
# In this case, the mounted filesystem will be visible only to the user that
# called this command, unless it was root (using sudo) though it would be
# pointless and you should just mount as usual.
#
# OPTIONS:
#   -f, --fuse   Use a FUSE filesystem with bindfs(1).
#   -t, --fstab  Add an entry to the system's fstab.
dotfiler_mount () {
    use_fuse=false
    update_fstab=false
    dir=$DEFAULT_DIR
    device=$HOME

    # Read arguments.
    read_flags=true
    pos=0
    while [ $# -gt 0 ]; do
        # Read flags.
        if $read_flags; then
            case $1 in
            -f|--fuse)
                use_fuse=true
                ;;
            -t|--fstab)
                update_fstab=true
                ;;
            -*)
                # Read grouped flags.
                while read -r flag; do
                    case $flag in
                    f)
                        use_fuse=true
                        ;;
                    t)
                        update_fstab=true
                        ;;
                    *)
                        stderr "Invalid flag \`$flag'."
                        stderr "Usage: $usage_mount"
                        exit 1
                        ;;
                    esac
                done <<EOF
$(echo "${1#-}" | fold -w 1)
EOF
                ;;
            *)
                read_flags=false
                continue
                ;;
            esac

            shift 1
            continue
        fi
        pos=$(( pos + 1 ))

        # Read positional arguments.
        if [ "$pos" -eq 1 ]; then
            if [ -n "$1" ]; then
                dir=$1
            else
                stderr "DIR must not be empty."
                stderr "Usage: $usage_mount"
                exit 1
            fi
        elif [ "$pos" -eq 2 ]; then
            if [ -n "$1" ]; then
                device=$1
            else
                stderr "DEVICE must not be empty."
                stderr "Usage: $usage_mount"
                exit 1
            fi
        else
            stderr "Usage: $usage_mount"
            exit 1
        fi

        shift 1
    done

    # Mount $device into $dir.
    if mountpoint -q "$dir"; then
        stderr "There is a mount point at \`$dir'."
        exit 1
    elif $use_fuse; then
        echo "Mounting into \`$dir' with FUSE filesystem. . ."
        bindfs -o nonempty,"$(is_root || echo no-allow-other)" "$device" "$dir"
    else
        echo "Mounting into \`$dir'. . ."
        mount --bind "$device" "$dir"
    fi

    # Update fstab.
    if $update_fstab; then
        dir=$(realpath "$dir")
        device=$(realpath "$device")

        if $use_fuse; then
            entry="bindfs#$device $dir fuse nonempty 0 0"
        else
            entry="$device $dir none bind"
        fi

        if ! grep -q "^$entry" /etc/fstab; then
            echo 'Adding entry to fstab. . .'
            echo "$entry" >> /etc/fstab
        else
            echo 'Found entry in fstab.'
        fi
    fi
}

# Unmounts $HOME from inside the repository.
#
# The positional argument is the mount point directory. If it is not provided,
# $DEFAULT_DIR is used.
#
# It requires root privileges. If the mounting was done with `--fuse`, it
# needs to use the same flag, and preferably be called by the same user.
#
# OPTIONS:
#   -f, --fuse   Unmount a FUSE filesystem.
#   -t, --fstab  Remove the entry from system's fstab.
dotfiler_umount () {
    use_fuse=false
    update_fstab=false
    dir=$DEFAULT_DIR

    # Read arguments.
    read_flags=true
    pos=0
    while [ $# -gt 0 ]; do
        # Read flags.
        if $read_flags; then
            case $1 in
            -f|--fuse)
                use_fuse=true
                ;;
            -t|--fstab)
                update_fstab=true
                ;;
            -*)
                # Read grouped flags.
                while read -r flag; do
                    case $flag in
                    f)
                        use_fuse=true
                        ;;
                    t)
                        update_fstab=true
                        ;;
                    *)
                        stderr "Invalid flag \`$flag'."
                        stderr "Usage: $usage_umount"
                        exit 1
                        ;;
                    esac
                done <<EOF
$(echo "${1#-}" | fold -w 1)
EOF
                ;;
            *)
                read_flags=false
                continue
                ;;
            esac

            shift 1
            continue
        fi
        pos=$(( pos + 1 ))

        # Read positional arguments.
        if [ "$pos" -eq 1 ]; then
            if [ -n "$1" ]; then
                dir=$1
            else
                stderr "DIR must not be empty."
                stderr "Usage: $usage_umount"
                exit 1
            fi
        else
            stderr "Usage: $usage_umount"
            exit 1
        fi

        shift 1
    done

    # Unmount $dir.
    if mountpoint -q "$dir"; then
        echo "Unmounting \`$dir'. . ."
        if $use_fuse; then
            fusermount -u "$dir"
        else
            umount "$dir"
        fi
    else
        stderr "No mount point was found at \`$dir'."
        exit 1
    fi

    # Update fstab.
    if $update_fstab; then
        dir=$(realpath "$dir")

        if grep -q "$dir" /etc/fstab; then
            echo 'Removing entry from fstab. . .'
            grep -v "$dir" /etc/fstab > /tmp/fstab.new
            mv -- /tmp/fstab.new /etc/fstab
        else
            echo 'No entries were found in fstab.'
        fi
    fi
}


# Main code
# =========

main () {
    if [ $# -eq 0 ]; then
        >&2 dotfiler_help
        exit 1
    fi

    cmd=$1
    shift

    case $cmd in
    init) dotfiler_init "$@" ;;
    add) dotfiler_add "$@" ;;
    rm) dotfiler_rm "$@" ;;
    mount) dotfiler_mount "$@" ;;
    umount) dotfiler_umount "$@" ;;
    -h|--help) dotfiler_help ;;
    -v|--version) dotfiler_version ;;
    *) >&2 dotfiler_help; exit 1 ;;
    esac
}


main "$@"

#!/bin/sh
#
# Dotfiler - maintain your dotfiles easily
#
# Copyright (c) 2019 Aryel Mota Góis <aryel.gois@gmail.com>
#
# MIT License

set -eu


program=$(basename "$0")
version=0.1.0

DEFAULT_DIR=home


# Documentation
# =============

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

Usage: $program init [DIR]
  or:  $program add FILE...
  or:  $program rm FILE...
  or:  $program mount [-ft] [DIR] [DEVICE]
  or:  $program umount [-ft] [DIR]
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

Copyright (c) 2019 Aryel Mota Góis <aryel.gois@gmail.com>.

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

# Checks if $1 starts with $2.
starts_with () {
    case $1 in
    $2*) return 0 ;;
    esac
    return 1
}

# Checks if effective user is root.
is_root () {
    if [ "$(id -u)" != "0" ]; then
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
dotfiler_init () {
    if [ $# -gt 1 ]; then
        stderr "Usage: $program init [DIR]"
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
        mkdir -p "$dir"
        cd "$dir"
        ;;
    esac

    # If the user is at $HOME or above, ask where to put the repository.
    if starts_with "$HOME" "$(pwd -P)"; then
        printf 'Where do you want to put the repository? '
        dir=
        read -r dir

        # Test user input and create directory if it does not exist.
        if [ -z "$dir" ]; then
            stderr 'You must enter a directory, or cd to somewhere else.'
            exit 1
        elif [ -e "$dir" ]; then
            if [ ! -d "$dir" ]; then
                stderr "\`$dir' is not a directory."
                exit 1
            fi
        else
            mkdir -p "$dir"
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
            printf '%s' "Use repository at \`$git_dir'? [Y/n] "
            input=
            read -r input

            if [ "$input" = 'n' ]; then
                git_dir=
            fi
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

    # Ask if should mount $HOME.
    printf "Would you like to mount your \$HOME? [Y/n] "
    input=
    read -r input
    if [ "$input" = 'Y' ]; then
        set --

        if ! is_root; then
            printf 'Would you like to use a FUSE filesystem? [Y/n] '
            input=
            read -r input
            if [ "$input" = 'Y' ]; then
                set -- --fuse
            fi
        fi

        printf 'Would you like to add an entry to fstab? [y/N] '
        input=
        read -r input
        if [ "$input" = 'y' ]; then
            set -- "$@" --fstab
        fi

        dotfiler_mount "$@" "$target"
    fi
}

# Adds files to the git index.
dotfiler_add () {
    :
}

# Removes files from the working tree and index.
dotfiler_rm () {
    :
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
    use_fuse=0
    update_fstab=0
    dir=$DEFAULT_DIR
    device=$HOME

    # Read arguments.
    read_flags=1
    pos=0
    while [ $# -gt 0 ]; do
        # Read flags.
        if [ "$read_flags" -eq 1 ]; then
            case $1 in
            -f|--fuse)
                use_fuse=1
                ;;
            -t|--fstab)
                update_fstab=1
                ;;
            -*)
                # Read grouped flags.
                while read -r flag; do
                    case $flag in
                    f)
                        use_fuse=1
                        ;;
                    t)
                        update_fstab=1
                        ;;
                    *)
                        stderr "Invalid flag \`$flag'."
                        stderr "Usage: $program mount [-ft] [DIR] [DEVICE]"
                        exit 1
                        ;;
                    esac
                done <<EOF
$(echo "${1#-}" | fold -w 1)
EOF
                ;;
            *)
                read_flags=0
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
                stderr "Usage: $program mount [-ft] [DIR] [DEVICE]"
                exit 1
            fi
        elif [ "$pos" -eq 2 ]; then
            if [ -n "$1" ]; then
                device=$1
            else
                stderr "DEVICE must not be empty."
                stderr "Usage: $program mount [-ft] [DIR] [DEVICE]"
                exit 1
            fi
        else
            stderr "Usage: $program mount [-ft] [DIR] [DEVICE]"
            exit 1
        fi

        shift 1
    done

    # Mount $device into $dir.
    if mountpoint -q "$dir"; then
        stderr "There is a mount point at \`$dir'."
        exit 1
    elif [ "$use_fuse" -ne 0 ]; then
        echo "Mounting into \`$dir' with FUSE filesystem. . ."
        bindfs -o nonempty,"$(is_root || echo no-allow-other)" "$device" "$dir"
    else
        echo "Mounting into \`$dir'. . ."
        mount --bind "$device" "$dir"
    fi

    # Update fstab.
    if [ "$update_fstab" -ne 0 ]; then
        dir=$(realpath "$dir")
        device=$(realpath "$device")

        if [ "$use_fuse" -ne 0 ]; then
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
    use_fuse=0
    update_fstab=0
    dir=$DEFAULT_DIR

    # Read arguments.
    read_flags=1
    pos=0
    while [ $# -gt 0 ]; do
        # Read flags.
        if [ "$read_flags" -eq 1 ]; then
            case $1 in
            -f|--fuse)
                use_fuse=1
                ;;
            -t|--fstab)
                update_fstab=1
                ;;
            -*)
                # Read grouped flags.
                while read -r flag; do
                    case $flag in
                    f)
                        use_fuse=1
                        ;;
                    t)
                        update_fstab=1
                        ;;
                    *)
                        stderr "Invalid flag \`$flag'."
                        stderr "Usage: $program umount [-ft] [DIR]"
                        exit 1
                        ;;
                    esac
                done <<EOF
$(echo "${1#-}" | fold -w 1)
EOF
                ;;
            *)
                read_flags=0
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
                stderr "Usage: $program umount [-ft] [DIR]"
                exit 1
            fi
        else
            stderr "Usage: $program umount [-ft] [DIR]"
            exit 1
        fi

        shift 1
    done

    # Unmount $dir.
    if mountpoint -q "$dir"; then
        echo "Unmounting \`$dir'. . ."
        if [ "$use_fuse" -ne 0 ]; then
            fusermount -u "$dir"
        else
            umount "$dir"
        fi
    else
        stderr "No mount point was found at \`$dir'."
        exit 1
    fi

    # Update fstab.
    if [ "$update_fstab" -ne 0 ]; then
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

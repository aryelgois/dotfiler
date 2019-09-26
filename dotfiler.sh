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
    # TODO
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
dotfiler_mount () {
    :
}

# Unmounts $HOME from inside the repository.
dotfiler_umount () {
    :
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

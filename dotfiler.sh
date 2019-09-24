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


# Commands
# ========

# Initializes a Dotfiler repository.
dotfiler_init () {
    :
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

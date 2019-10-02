# Dotfiler

Maintain your dotfiles easily.


## What is it?

A tool to help with tracking your dotfiles
in a git repository,
so you can take them anywhere.


## How does it work?

You keep a hard link of your `$HOME`
inside the repository
and git does the hard work for you.

Dotfiler helps with mounting/unmounting
and adding files to the git index.
Since there are many other files
you don't want to track,
a `.gitignore` excludes everything
except what you explicitly added.

Once you update the working tree
with `git pull` or changing branches,
all your dotfiles are automatically updated
(if your `$HOME` is mounted inside the repo).
If there are merge conflicts though,
you will need to solve them.


## Installing

Simply clone the repository and run `make install`.

    git clone https://github.com/aryelgois/dotfiler.git && cd dotfiler

Note that
it will need root privileges
to install system-wide.
You may install on your user directory
with `make prefix=~/.local install`,
just make sure that
`$HOME/.local/bin` is in your `$PATH`.

If you have [help2man] installed,
a man page will be generated for you.


## Using

Initialize a new repository with `dotfiler init`
or clone an existing one,
then make sure your `$HOME` has a hard link
at the mount point
with `dotfiler mount`.

Enter the repo directory
and use `dotfiler add` to add your dotfiles
to the index.

And don't forget to `git commit`.


## Commands

You can get a summary
about the commands
with `--help`.

### dotfiler init

Prepares everything for you,
from a brand new git repository,
with a basic `README` and `.gitignore`,
to already mounting your `$HOME`,
if you wish.

By default,
Dotfiler creates a `home` directory,
but you can pass a different `DIR` to use,
which doesn't even need to be at the repository root.
You may call this command
with different arguments
to organize your dotfiles
in multiple directories.

### dotfiler add

Adds one or more files
to the re-included files in `.gitignore`
and to the git index.

The entries in the `.gitignore` file
don't need to be alphabetically ordered,
but you can maintain it if you will.
They only have to be ordered with
a parent directory before its contents.

If an argument is a directory,
a glob pattern is added
to re-include all files
inside of it.
It is a convenience feature
for directories with dynamic content,
but adding each file explicitly
is preferable.

### dotfiler rm

### dotfiler mount

Mounts `$HOME`
or another `DEVICE`
at the `DIR` mount point
(default is `home`)
inside the repository.

It allows your dotfiles
to be applied
outside the repository
while keeping it organized.

To do this,
a hard link is created
with [mount(8)].
Since it requires root privileges,
a FUSE filesystem is supported
with [bindfs],
if you pass
the `--fuse` flag.
In this case,
it will be visible
only for you.

All files that exist in the mount point
prior to this command
will be intact.
They will only be inaccessible
while the mount is in place.

You only need to keep the hard link
while interacting with the repository,
but you may persist it
with `--fstab`,
which adds an entry at `/etc/fstab`.

### dotfiler umount

Unmounts a mount point `DIR`
inside the repository,
which defaults to `home`.

It undos the hard link to `$HOME`
with [umount(8)].
If the mounting was done with `--fuse`,
you need to pass this flag as well.

It also accepts `--fstab`
to remove the matching entry
from `/etc/fstab`.


## [Changelog]

See the [CHANGELOG.md][changelog].


## [License]

See the [LICENSE].


[changelog]: CHANGELOG.md
[license]: LICENSE

[bindfs]: https://bindfs.org
[help2man]: https://www.gnu.org/software/help2man

[mount(8)]: https://linux.die.net/man/8/mount
[umount(8)]: https://linux.die.net/man/8/umount

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

### dotfiler add

### dotfiler rm

### dotfiler mount

### dotfiler umount


## [Changelog]

See the [CHANGELOG.md][changelog].


## [License]

See the [LICENSE].


[changelog]: CHANGELOG.md
[license]: LICENSE

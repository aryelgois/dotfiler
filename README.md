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


## [Changelog]

See the [CHANGELOG.md][changelog].


## [License]

See the [LICENSE].


[changelog]: CHANGELOG.md
[license]: LICENSE

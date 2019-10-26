SHELL = /bin/sh

# Command variables.
GZIP = gzip
HELP2MAN = help2man
HELP2MANFLAGS = --no-info --locale en_US
INSTALL = install
SHELLCHECK = shellcheck

# Install commands.
INSTALL_PROGRAM = $(INSTALL)
INSTALL_DATA = $(INSTALL) -m 644
INSTALL_DIR = $(INSTALL) -d

# Common prefix for installation directories.
prefix = /usr/local
exec_prefix = $(prefix)
datarootdir = $(prefix)/share
# Where to put the executable.
bindir = $(exec_prefix)/bin
# Where to put the manual files.
mandir = $(datarootdir)/man
man1dir = $(mandir)/man1

# The program.
program = dotfiler
description = maintain your dotfiles easily
source = $(program).sh
manual = $(program).1

# Output files.
program_out = $(DESTDIR)$(bindir)/$(program)
manual_out = $(DESTDIR)$(man1dir)/$(manual)


.PHONY: all
all: check $(program) man


.PHONY: check
check: $(source)
	$(SHELLCHECK) $<


.PHONY: install
install: $(program) man installdirs
	$(INSTALL_PROGRAM) $(program) $(program_out)
	-$(INSTALL_DATA) $(manual) $(manual_out) \
		&& $(GZIP) $(manual_out)

.PHONY: installdirs
installdirs:
	$(INSTALL_DIR) $(DESTDIR)$(bindir)
	$(INSTALL_DIR) $(DESTDIR)$(man1dir)


.PHONY: man
man: $(manual)


$(manual): $(program)
	-$(HELP2MAN) --output=$@ --name='$(description)' \
		$(HELP2MANFLAGS) ./$<

$(program): $(source)
	cp $< $@


.PHONY: uninstall
uninstall:
	-rm $(program_out)
	-rm $(manual_out)*


.PHONY: clean
clean:
	-rm $(program)
	-rm $(manual)

# Install the launchers.
#
# Both are single self-contained shell scripts, so there is nothing to build --
# "install" just copies them into place under the names their own
# --self-update expects to overwrite.

PREFIX  ?= /usr/local
BINDIR  ?= $(PREFIX)/bin
INSTALL ?= install

# /usr/local/bin is root-owned, so the copy is elevated. Override with
# `make SUDO=` when running as root or installing into a prefix you own,
# e.g. `make PREFIX=$$HOME/.local SUDO=`.
SUDO ?= sudo

.PHONY: all install install-claude install-codex uninstall check help

all: install

install: install-claude install-codex

install-claude: bin/claude
	$(SUDO) $(INSTALL) -D -m 755 bin/claude $(BINDIR)/claude-podman
	@echo "installed $(BINDIR)/claude-podman"

install-codex: bin/codex
	$(SUDO) $(INSTALL) -D -m 755 bin/codex $(BINDIR)/codex-podman
	@echo "installed $(BINDIR)/codex-podman"

uninstall:
	$(SUDO) rm -f $(BINDIR)/claude-podman $(BINDIR)/codex-podman

# Parse-only check; catches syntax errors without running either launcher.
check:
	bash -n bin/claude
	bash -n bin/codex
	@echo "ok"

help:
	@echo "make [all]          install both launchers into $(BINDIR)"
	@echo "make install-claude install claude-podman only"
	@echo "make install-codex  install codex-podman only"
	@echo "make uninstall      remove both from $(BINDIR)"
	@echo "make check          syntax-check both launchers"
	@echo ""
	@echo "Variables: PREFIX (default /usr/local), BINDIR, SUDO (set empty to skip sudo)"

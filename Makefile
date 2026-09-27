# Install the launchers, or build the images they run.
#
# Both launchers are single self-contained shell scripts, so "install" just
# copies them into place under the names their own --self-update expects to
# overwrite. "images" builds the claude-code and codex images locally, for the
# launchers' --local.

PREFIX  ?= /usr/local
BINDIR  ?= $(PREFIX)/bin
INSTALL ?= install

# /usr/local/bin is root-owned, so the copy is elevated. Override with
# `make SUDO=` when running as root or installing into a prefix you own,
# e.g. `make PREFIX=$$HOME/.local SUDO=`.
SUDO ?= sudo

# A Containerfile of your own to layer under both images: ./Containerfile
# (gitignored) if it exists, or name one, e.g.
# `make images CONTAINERFILE=examples/Containerfile.rust-nightly`.
# `make images CONTAINERFILE=` builds the stock images. CI runs the build
# scripts directly, so it never picks this up.
CONTAINERFILE ?= $(wildcard Containerfile)
export CONTAINERFILE

.PHONY: all install install-claude install-codex uninstall images image-claude image-codex check help

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

images: image-claude image-codex

image-claude:
	./devops/build-claude.sh

image-codex:
	./devops/build-codex.sh

# Parse-only check; catches syntax errors without running anything.
check:
	bash -n bin/claude
	bash -n bin/codex
	sh -n devops/base-image.sh
	sh -n devops/build-claude.sh
	sh -n devops/build-codex.sh
	@echo "ok"

help:
	@echo "make [all]          install both launchers into $(BINDIR)"
	@echo "make install-claude install claude-podman only"
	@echo "make install-codex  install codex-podman only"
	@echo "make uninstall      remove both from $(BINDIR)"
	@echo "make images         build both images locally, for --local"
	@echo "make image-claude   build the claude-code image only"
	@echo "make image-codex    build the codex image only"
	@echo "make check          syntax-check the launchers and build scripts"
	@echo ""
	@echo "Variables: PREFIX (default /usr/local), BINDIR, SUDO (set empty to skip sudo)"
	@echo "Images:    CONTAINERFILE (default ./Containerfile if present), BASE_IMAGE, NO_CACHE=1"

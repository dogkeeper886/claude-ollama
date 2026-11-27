# claude-ollama: install the launcher and create or update its config files.
# Run `make` for the targets. Override BINDIR on the command line, e.g.
# `make install BINDIR=/usr/local/bin`; move the config files with XDG_CONFIG_HOME.

SHELL := /bin/bash
BINDIR ?= $(HOME)/bin
# claude-ollama.sh finds its config through XDG_CONFIG_HOME, so CONFIG_DIR follows
# it too; a CONFIG_DIR of its own would write files the launcher never reads.
ifeq ($(origin CONFIG_DIR),command line)
$(error set XDG_CONFIG_HOME, not CONFIG_DIR: claude-ollama.sh reads only XDG_CONFIG_HOME)
endif
CONFIG_DIR := $(or $(XDG_CONFIG_HOME),$(HOME)/.config)/claude-ollama
CONFIG := $(CONFIG_DIR)/config
SCRIPT := $(CURDIR)/claude-ollama.sh
LINK := $(BINDIR)/claude-ollama

.DEFAULT_GOAL := help
.PHONY: help install uninstall config check

help: ## Show this help
	@echo "Usage: make <target>"
	@echo
	@awk 'BEGIN { FS = ":.*## " } /^[a-z]+:.*## / { printf "  %-10s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo
	@echo "  BINDIR     = $(BINDIR)"
	@echo "  CONFIG_DIR = $(CONFIG_DIR)"

install: ## Link claude-ollama.sh into BINDIR as claude-ollama
	@if [ -e "$(LINK)" ] || [ -L "$(LINK)" ]; then \
	  if [ "$$(readlink "$(LINK)")" != "$(SCRIPT)" ]; then \
	    echo "$(LINK) exists and is not a link to $(SCRIPT); left it" >&2; exit 1; \
	  fi; \
	fi
	@mkdir -p "$(BINDIR)"
	@ln -sfn "$(SCRIPT)" "$(LINK)"
	@echo "linked $(LINK) -> $(SCRIPT)"

uninstall: ## Remove the claude-ollama link from BINDIR
	@if [ "$$(readlink "$(LINK)")" = "$(SCRIPT)" ]; then \
	  rm "$(LINK)" && echo "removed $(LINK)"; \
	else \
	  echo "$(LINK) is not a link to $(SCRIPT); left it"; \
	fi

config: ## Create config and load.conf in CONFIG_DIR, or update them and keep your values
	@./merge-conf.sh config.example.conf "$(CONFIG)"
	@./merge-conf.sh load.conf "$(CONFIG_DIR)/load.conf"

check: ## Check the script's syntax, with shellcheck when installed
	@bash -n claude-ollama.sh && echo "bash -n: ok"
	@if command -v shellcheck >/dev/null; then shellcheck claude-ollama.sh && echo "shellcheck: ok"; \
	else echo "shellcheck: not installed, skipped"; fi

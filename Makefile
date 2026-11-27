# claude-ollama: install the launcher and create its config.
# Run `make` for the targets. Override BINDIR or CONFIG_DIR on the command line,
# e.g. `make install BINDIR=/usr/local/bin`.

SHELL := /bin/bash
BINDIR ?= $(HOME)/bin
CONFIG_DIR ?= $(or $(XDG_CONFIG_HOME),$(HOME)/.config)/claude-ollama
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

config: ## Create the config in CONFIG_DIR from config.example.conf
	@if [ -e "$(CONFIG)" ]; then \
	  echo "$(CONFIG) exists; edit it by hand"; \
	else \
	  mkdir -p "$(CONFIG_DIR)" && cp config.example.conf "$(CONFIG)" && echo "created $(CONFIG)"; \
	fi

check: ## Check the script's syntax, with shellcheck when installed
	@bash -n claude-ollama.sh && echo "bash -n: ok"
	@if command -v shellcheck >/dev/null; then shellcheck claude-ollama.sh && echo "shellcheck: ok"; \
	else echo "shellcheck: not installed, skipped"; fi

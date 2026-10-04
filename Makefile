IMAGE_NAME := memo-sh
CONTAINER_NAME := $(IMAGE_NAME)
VOLUME_MOUNT := -v $(shell pwd):/opt

MEMO_INSTALL_DIR := $(HOME)/.local/bin
ZSH_COMPLETION_DIR := /usr/local/share/zsh/site-functions
BASH_COMPLETION_DIR := /usr/local/share/bash-completion/completions
ZSH_COMPLETION_FALLBACK := $(HOME)/.local/share/zsh/site-functions
BASH_COMPLETION_FALLBACK := $(HOME)/.local/share/bash-completion/completions

# Ensures it does not interferes with local files/directories named test or build etc...
.PHONY: test build install install-dev uninstall

dev:
	chmod +x $(CURDIR)/memo.sh
	@printf "Symlinking $(CURDIR)/memo.sh -> $(MEMO_INSTALL_DIR)/memo...\n"
	mkdir -p $(MEMO_INSTALL_DIR)
	ln -sf $(CURDIR)/memo.sh $(MEMO_INSTALL_DIR)/memo

	@printf "Symlinking completions...\n"
	@if mkdir -p "$(ZSH_COMPLETION_DIR)" 2>/dev/null && [ -w "$(ZSH_COMPLETION_DIR)" ]; then \
		ln -sf $(CURDIR)/completions/_memo $(ZSH_COMPLETION_DIR)/_memo; \
		printf "Zsh completion installed to $(ZSH_COMPLETION_DIR)/_memo\n"; \
	else \
		mkdir -p "$(ZSH_COMPLETION_FALLBACK)"; \
		ln -sf $(CURDIR)/completions/_memo $(ZSH_COMPLETION_FALLBACK)/_memo; \
		printf "Zsh completion installed to $(ZSH_COMPLETION_FALLBACK)/_memo\n"; \
		printf "Add this to your ~/.zshrc before compinit to enable it:\n"; \
		printf "  fpath=( $(ZSH_COMPLETION_FALLBACK) \$$fpath )\n"; \
	fi
	@if mkdir -p "$(BASH_COMPLETION_DIR)" 2>/dev/null && [ -w "$(BASH_COMPLETION_DIR)" ]; then \
		ln -sf $(CURDIR)/completions/memo.bash $(BASH_COMPLETION_DIR)/memo; \
		printf "Bash completion installed to $(BASH_COMPLETION_DIR)/memo\n"; \
	else \
		mkdir -p "$(BASH_COMPLETION_FALLBACK)"; \
		ln -sf $(CURDIR)/completions/memo.bash $(BASH_COMPLETION_FALLBACK)/memo; \
		printf "Bash completion installed to $(BASH_COMPLETION_FALLBACK)/memo\n"; \
		printf "The per-user dir is picked up automatically when bash-completion is installed.\n"; \
	fi

	@printf "Installation complete!\n"
	@printf "Ensure $(MEMO_INSTALL_DIR) is in your shell's PATH.\n"

install:
	@printf "Installing memo bash script to $(MEMO_INSTALL_DIR)...\n"
	mkdir -p $(MEMO_INSTALL_DIR)
	install -m 0700 memo.sh $(MEMO_INSTALL_DIR)/memo

	@printf "Installing completions...\n"
	@if mkdir -p "$(ZSH_COMPLETION_DIR)" 2>/dev/null && [ -w "$(ZSH_COMPLETION_DIR)" ]; then \
		install -m 0644 completions/_memo $(ZSH_COMPLETION_DIR)/_memo; \
		printf "Zsh completion installed to $(ZSH_COMPLETION_DIR)/_memo\n"; \
	else \
		mkdir -p "$(ZSH_COMPLETION_FALLBACK)"; \
		install -m 0644 completions/_memo $(ZSH_COMPLETION_FALLBACK)/_memo; \
		printf "Zsh completion installed to $(ZSH_COMPLETION_FALLBACK)/_memo\n"; \
		printf "Add this to your ~/.zshrc before compinit to enable it:\n"; \
		printf "  fpath=( $(ZSH_COMPLETION_FALLBACK) \$$fpath )\n"; \
	fi
	@if mkdir -p "$(BASH_COMPLETION_DIR)" 2>/dev/null && [ -w "$(BASH_COMPLETION_DIR)" ]; then \
		install -m 0644 completions/memo.bash $(BASH_COMPLETION_DIR)/memo; \
		printf "Bash completion installed to $(BASH_COMPLETION_DIR)/memo\n"; \
	else \
		mkdir -p "$(BASH_COMPLETION_FALLBACK)"; \
		install -m 0644 completions/memo.bash $(BASH_COMPLETION_FALLBACK)/memo; \
		printf "Bash completion installed to $(BASH_COMPLETION_FALLBACK)/memo\n"; \
		printf "The per-user dir is picked up automatically when bash-completion is installed.\n"; \
	fi

	@printf "Installation complete!\n"
	@printf "Ensure $(MEMO_INSTALL_DIR) is in your shell's PATH.\n"	
uninstall:
	@printf "Deleting $(MEMO_INSTALL_DIR)/memo\n"
	@rm -rf $(MEMO_INSTALL_DIR)/memo
	@printf "Deleting completion files\n"
	@rm -f $(ZSH_COMPLETION_DIR)/_memo
	@rm -f $(BASH_COMPLETION_DIR)/memo
	@rm -f $(ZSH_COMPLETION_FALLBACK)/_memo
	@rm -f $(BASH_COMPLETION_FALLBACK)/memo

	@printf "Uninstall complete!\n"

docker/build-image:
	@docker build -t $(IMAGE_NAME) .

docker/shell:
	@docker run --rm -it --name $(CONTAINER_NAME) $(VOLUME_MOUNT) $(IMAGE_NAME) /bin/bash; \

test:
	@docker run --rm $(VOLUME_MOUNT) $(IMAGE_NAME) bats test/$(file)

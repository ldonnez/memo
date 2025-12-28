IMAGE_NAME := memo-sh
CONTAINER_NAME := $(IMAGE_NAME)
VOLUME_MOUNT := -v $(shell pwd):/opt

MEMO_INSTALL_DIR := ~/.local/bin

# Ensures it does not interferes with local files/directories named test or build etc...
.PHONY: test build install install-dev uninstall

dev:
	chmod +x $(CURDIR)/memo.sh
	@printf "Symlinking $(CURDIR)/memo.sh -> $(MEMO_INSTALL_DIR)/memo...\n"
	mkdir -p $(MEMO_INSTALL_DIR)
	ln -sf $(CURDIR)/memo.sh $(MEMO_INSTALL_DIR)/memo

	@printf "Installation complete!\n"
	@printf "Ensure $(MEMO_INSTALL_DIR) is in your shell's PATH.\n"

install:
	@printf "Installing memo bash script to $(MEMO_INSTALL_DIR)...\n"
	mkdir -p $(MEMO_INSTALL_DIR)
	install -m 0700 memo.sh $(MEMO_INSTALL_DIR)/memo

	@printf "Installation complete!\n"
	@printf "Ensure $(MEMO_INSTALL_DIR) is in your shell's PATH.\n"
	
uninstall:
	@printf "Deleting $(MEMO_INSTALL_DIR)/memo\n"
	@rm -rf $(MEMO_INSTALL_DIR)/memo

	@printf "Uninstall complete!\n"

docker/build-image:
	@docker build -t $(IMAGE_NAME) .

docker/shell:
	@docker run --rm -it --name $(CONTAINER_NAME) $(VOLUME_MOUNT) $(IMAGE_NAME) /bin/bash; \

test:
	@docker run --rm $(VOLUME_MOUNT) $(IMAGE_NAME) bats test/$(file)

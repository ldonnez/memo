IMAGE_NAME := memo-sh
CONTAINER_NAME := $(IMAGE_NAME)
VOLUME_MOUNT := -v $(shell pwd):/opt

GO_BINARY_NAME := cache_builder

MEMO_INSTALL_DIR := ~/.local/bin
CACHE_BUILDER_INSTALL_DIR := ~/.local/libexec/memo

# Ensures it does not interferes with local files/directories named test or build etc...
.PHONY: test build install install-dev clean uninstall

build:
	@printf "Building $GO_BINARY_NAME binary...\n"
	go build -o bin/$(GO_BINARY_NAME) ./cmd/cache_builder

dev: build
	@printf "Symlinking $(CURDIR)/bin/$(GO_BINARY_NAME) -> $(CACHE_BUILDER_INSTALL_DIR)/$(GO_BINARY_NAME)...\n"
	mkdir -p $(CACHE_BUILDER_INSTALL_DIR)
	ln -sf $(CURDIR)/bin/$(GO_BINARY_NAME) $(CACHE_BUILDER_INSTALL_DIR)/$(GO_BINARY_NAME)

	@printf "Symlinking $(CURDIR)/memo.sh -> $(MEMO_INSTALL_DIR)/memo...\n"
	mkdir -p $(MEMO_INSTALL_DIR)
	ln -sf $(CURDIR)/memo.sh $(MEMO_INSTALL_DIR)/memo

	@printf "Installation complete!\n"
	@printf "Ensure $(MEMO_INSTALL_DIR) is in your shell's PATH.\n"

install: build
	@printf "Installing cache_builder binary to $(CACHE_BUILDER_INSTALL_DIR)...\n"
	mkdir -p $(CACHE_BUILDER_INSTALL_DIR)
	install -m 0700 bin/$(GO_BINARY_NAME) $(CACHE_BUILDER_INSTALL_DIR)/$(GO_BINARY_NAME)

	@printf "Installing memo bash script to $(MEMO_INSTALL_DIR)...\n"
	mkdir -p $(MEMO_INSTALL_DIR)
	install -m 0700 memo.sh $(MEMO_INSTALL_DIR)/memo

	@printf "Installation complete!\n"
	@printf "Ensure $(MEMO_INSTALL_DIR) is in your shell's PATH.\n"
	
uninstall:
	@printf "Deleting $(CACHE_BUILDER_INSTALL_DIR)\n"
	@rm -rf $(CACHE_BUILDER_INSTALL_DIR)

	@printf "Deleting $(MEMO_INSTALL_DIR)/memo\n"
	@rm -rf $(MEMO_INSTALL_DIR)/memo

	@printf "Uninstall complete!\n"

clean:
	@printf "Cleaning up...\n"
	rm -f bin/$(GO_BINARY_NAME)
	@printf "Cleanup complete!\n"

docker/build-image:
	@docker build -t $(IMAGE_NAME) .

docker/shell:
	@docker run --rm -it --name $(CONTAINER_NAME) $(VOLUME_MOUNT) $(IMAGE_NAME) /bin/bash; \

test:
	@docker run --rm $(VOLUME_MOUNT) $(IMAGE_NAME) go test -v ./...
	@docker run --rm $(VOLUME_MOUNT) $(IMAGE_NAME) bats test/$(file)

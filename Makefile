IMAGE_NAME := memo-sh
CONTAINER_NAME := $(IMAGE_NAME)
VOLUME_MOUNT := -v $(shell pwd):/opt

.PHONY: test

build:
	@docker build -t $(IMAGE_NAME) .

shell:
	@docker run --rm -it --name $(CONTAINER_NAME) $(VOLUME_MOUNT) $(IMAGE_NAME) /bin/bash; \

test:
	@docker run --rm $(VOLUME_MOUNT) $(IMAGE_NAME) go test -v ./...
	@docker run --rm $(VOLUME_MOUNT) $(IMAGE_NAME) bats test/$(file)

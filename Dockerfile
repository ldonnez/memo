FROM golang:1.24-bookworm

# Install dependencies
RUN apt-get update && apt-get install -y \
    bash bats bats-support bats-assert bats file git gpg coreutils moreutils \
    && apt-get clean

WORKDIR /opt

# Set entrypoint
ENTRYPOINT ["/bin/bash"]

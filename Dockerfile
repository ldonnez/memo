FROM golang:1.24-trixie

# Install dependencies
RUN apt-get update && apt-get install -y \
    bash bats bats-support bats-assert git gpg coreutils moreutils \
    && apt-get clean

WORKDIR /opt

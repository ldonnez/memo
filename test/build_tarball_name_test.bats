#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

@test "returns memo_Darwin_x86_64.tar.gz when arch is x86_64 and OS is Darwin" {
  # Mock uname
  # shellcheck disable=SC2329
  uname() {
    if [ "$1" = "-m" ]; then
      echo "x86_64"
    elif [ "$1" = "-s" ]; then
      echo "Darwin"
    fi
  }

  run _build_tarball_name
  assert_success
  assert_output "memo_Darwin_x86_64.tar.gz"
}

@test "returns memo_Linux_x86_64.tar.gz when arch is x86_64 and OS is Linux" {
  # Mock uname
  # shellcheck disable=SC2329
  uname() {
    if [ "$1" = "-m" ]; then
      echo "x86_64"
    elif [ "$1" = "-s" ]; then
      echo "Linux"
    fi
  }

  run _build_tarball_name
  assert_success
  assert_output "memo_Linux_x86_64.tar.gz"
}

@test "returns memo_Darwin_arm64.tar.gz when arch is arm64 and OS is Darwin" {
  # Mock uname
  # shellcheck disable=SC2329
  uname() {
    if [ "$1" = "-m" ]; then
      echo "arm64"
    elif [ "$1" = "-s" ]; then
      echo "Darwin"
    fi
  }

  run _build_tarball_name
  assert_success
  assert_output "memo_Darwin_arm64.tar.gz"
}

@test "returns memo_Linux_arm64.tar.gz when arch is aarch64 and OS is Linux" {
  # Mock uname
  # shellcheck disable=SC2329
  uname() {
    if [ "$1" = "-m" ]; then
      echo "aarch64"
    elif [ "$1" = "-s" ]; then
      echo "Linux"
    fi
  }

  run _build_tarball_name
  assert_success
  assert_output "memo_Linux_arm64.tar.gz"
}

@test "returns Unsupported OS when OS is Windows" {
  # Mock uname
  # shellcheck disable=SC2329
  uname() {
    if [ "$1" = "-m" ]; then
      echo "x86_64"
    elif [ "$1" = "-s" ]; then
      echo "Windows"
    fi
  }

  run _build_tarball_name
  assert_failure
  assert_output "Unsupported OS: Windows"
}

@test "returns unsupported arch when arch is i686" {
  # Mock uname
  # shellcheck disable=SC2329
  uname() {
    if [ "$1" = "-m" ]; then
      echo "i686"
    elif [ "$1" = "-s" ]; then
      echo "Linux"
    fi
  }

  run _build_tarball_name
  assert_failure
  assert_output "Unsupported arch: i686"
}

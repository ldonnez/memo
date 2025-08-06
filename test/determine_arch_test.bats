#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

@test "returns x86_64 when arch is x86_64" {

  # Mock uname
  # shellcheck disable=SC2329
  uname() {
    printf "x86_64"
  }

  run _determine_arch
  assert_success
  assert_output "x86_64"
}

@test "returns arm64 when arch is aarch64" {

  # Mock uname
  # shellcheck disable=SC2329
  uname() {
    printf "aarch64"
  }

  run _determine_arch
  assert_success
  assert_output "arm64"
}

@test "returns arm64 when arch is arm64" {

  # Mock uname
  # shellcheck disable=SC2329
  uname() {
    printf "arm64"
  }

  run _determine_arch
  assert_success
  assert_output "arm64"
}

@test "returns Unsupported arch when arch is i686" {

  # Mock uname
  # shellcheck disable=SC2329
  uname() {
    printf "i686"
  }

  run _determine_arch
  assert_failure
  assert_output "Unsupported arch: i686"
}

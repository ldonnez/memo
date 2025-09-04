#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

@test "success when file is extension md" {
  run _is_supported_extension "test.md"
  assert_success
}

@test "success when file is extension org" {
  run _is_supported_extension "test.org"
  assert_success
}

@test "success when file is extension txt" {
  run _is_supported_extension "test.org"
  assert_success
}

@test "success when file is extension md.gpg" {
  run _is_supported_extension "test.md.gpg"
  assert_success
}

@test "fail when file has no extension" {
  run _is_supported_extension "test"
  assert_failure
  assert_output "Extension:  not supported"
}

@test "fail when file extension just gpg" {
  run _is_supported_extension "test.gpg"
  assert_failure
  assert_output "Extension:  not supported"
}

@test "fail when file is extension jpg" {
  run _is_supported_extension "test.jpg"
  assert_failure
  assert_output "Extension: jpg not supported"
}

@test "fail when extension is not in SUPPORTED_EXTENSIONS variable" {
  # Run in seperate subshell to avoid collision
  (
    local SUPPORTED_EXTENSIONS="org,txt"
    run _is_supported_extension "test.md"
    assert_failure
    assert_output "Extension: md not supported"
  )
}

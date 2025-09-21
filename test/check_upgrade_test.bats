#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

@test "Already up to date current and latest version is the same" {
  # Run in different subshell to avoid collision
  (
    local VERSION="0.1.0"
    local latest="v0.1.0"

    run _check_upgrade "$latest"
    assert_failure
    assert_output "Already up to date"
  )
}

@test "Upgrade available current version patch version before latest" {
  # Run in different subshell to avoid collision
  (
    local VERSION="0.1.0"
    local latest="v0.1.1"

    run _check_upgrade "$latest"
    assert_success
    assert_output "Upgrade available: v$VERSION -> $latest"
  )
}

@test "Upgrade available current version minor version before latest" {
  # Run in different subshell to avoid collision
  (
    local VERSION="0.1.0"
    local latest="v0.1.1"

    run _check_upgrade "$latest"
    assert_success
    assert_output "Upgrade available: v$VERSION -> $latest"
  )
}

@test "Upgrade available current major minor version before latest" {
  # Run in different subshell to avoid collision
  (
    local VERSION="0.1.0"
    local latest="v1.0.0"

    run _check_upgrade "$latest"
    assert_success
    assert_output "Upgrade available: v$VERSION -> $latest"
  )
}

@test "Current version is newer then latest" {
  # Run in different subshell to avoid collision
  (
    local VERSION="0.2.0"
    local latest="v0.1.0"

    run _check_upgrade "$latest"
    assert_failure
    assert_output "Current version (v$VERSION) is newer than latest $latest?"
  )
}

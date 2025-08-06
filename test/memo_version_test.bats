#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

@test "prints current version" {
  # Run in subshell to avaoid collision with other tests
  (
    local VERSION="vx.x.x"

    run memo_version
    assert_success
    assert_output "$VERSION"
  )
}

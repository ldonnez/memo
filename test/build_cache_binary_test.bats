#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEST_DIR="$(mktemp -d)"
  BINARY_PATH="$TEST_DIR/bin/cache_builder"

  # shellcheck source=memo.sh
  source "memo.sh"
}

teardown() {
  rm -rf "$TEST_DIR"
}

@test "build_cache_binary builds binary if missing" {
  run build_cache_binary "/opt" "$BINARY_PATH"
  assert_success
  assert_output "Building cache binary..."
}

@test "build_cache_binary does not rebuild if binary already exists" {
  mkdir -p "$TEST_DIR/bin"
  local binary="$BINARY_PATH"
  printf "built" >"$binary"

  chmod +x "$binary"

  run build_cache_binary "/opt" "$BINARY_PATH"
  assert_success
  assert_output ""
}

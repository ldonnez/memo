#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  TEMP="$(mktemp -d)"

  # shellcheck source=memo.sh
  source "memo.sh"
}

teardown() {
  rm -rf "$TEMP"
}

@test "loads config from config file" {
  # Run in subshell to prevent collision in other tests
  (
    mkdir -p "$TEMP/.config/memo"

    local config_file="$TEMP/.config/memo/config"

    cat >"$config_file" <<EOF
KEY_IDS="test@example.com"
EDITOR_CMD="vim"
EOF

    _load_config "$config_file"
    assert_equal "$EDITOR_CMD" "vim"
    assert_equal "$KEY_IDS" "test@example.com"
  )
}

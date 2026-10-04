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
GPG_RECIPIENTS="test@example.com"
EDITOR_CMD="vim"
EOF

    _load_config "$config_file"
    assert_equal "$EDITOR_CMD" "vim"
    assert_equal "$GPG_RECIPIENTS" "test@example.com"
  )
}

@test "an unusable EXTENSION keeps help and version working" {
  (
    mkdir -p "$TEMP/.config/memo"

    cat >"$TEMP/.config/memo/config" <<EOF
EXTENSION=""
EOF

    # main reads the config from $XDG_CONFIG_HOME, so it is pointed at the
    # throwaway one instead of the suite-wide config.
    export XDG_CONFIG_HOME="$TEMP/.config"

    run main version
    assert_success
    assert_output --partial "v$VERSION"

    run main help
    assert_success
    assert_output --partial "Usage: memo [FILE]"

    # Anything that works on notes is still refused, and the reason is printed
    run main today
    assert_failure
    assert_output --partial "EXTENSION must be a bare extension"
  )
}

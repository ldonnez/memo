#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

@test "Uninstalls memo when confirming" {
  # Run in subshell to avaoid collision with other tests
  (
    local _CACHE_BUILDER_DIR="/tmp/cache_builder/bin"
    local temp_script_path="/tmp/memo"

    # mock cache_builder path and memo script path
    mkdir -p "$_CACHE_BUILDER_DIR"
    mkdir -p "$temp_script_path"

    # mock memo binary to delete
    touch "$temp_script_path/memo"

    # Mock _resolve_script_path
    # shellcheck disable=SC2329
    _resolve_script_path() { printf "%s\n" "$temp_script_path"; }

    run memo_uninstall <<<""
    assert_success
    assert_output "Proceeding with uninstall...
Deleted $_CACHE_BUILDER_DIR
Deleted $temp_script_path/memo
Uninstall completed."
  )
}

@test "Does not uninstall when not confirming" {
  # Run in subshell to avaoid collision with other tests
  (
    run memo_uninstall <<<"n"
    assert_success
    assert_output "Uninstall cancelled."
  )
}

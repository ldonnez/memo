#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

@test "Uninstalls memo when confirming" {
  # Run in subshell to avoid collision with other tests
  (
    local temp_script_path="/tmp/memo"

    # mock memo script path
    mkdir -p "$temp_script_path"

    # mock memo binary to delete
    touch "$temp_script_path/memo"

    local sys_bash="/usr/local/share/bash-completion/completions"
    local zsh_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions"
    local fallback_bash="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions"

    local test_sys_bash=false
    if [ -w "$(dirname "$sys_bash")" ]; then
      test_sys_bash=true
      mkdir -p "$sys_bash"
      touch "$sys_bash/memo"
    fi

    mkdir -p "$zsh_dir" "$fallback_bash"
    touch "$zsh_dir/_memo" "$fallback_bash/memo"

    # Mock _resolve_script_path
    # shellcheck disable=SC2317,SC2329
    _resolve_script_path() { printf "%s\n" "$temp_script_path"; }

    run memo_uninstall <<<""
    assert_success
    assert_output --partial "Proceeding with uninstall..."
    assert_output --partial "Deleted $temp_script_path/memo"
    assert_output --partial "Deleted completion files"
    assert_output --partial "Uninstall completed."

    refute [ -e "$zsh_dir/_memo" ]
    refute [ -e "$fallback_bash/memo" ]

    if [ "$test_sys_bash" = true ]; then
      refute [ -e "$sys_bash/memo" ]
    fi
  )
}

@test "Does not uninstall when not confirming" {
  # Run in subshell to avoid collision with other tests
  (
    run memo_uninstall <<<"n"
    assert_success
    assert_output "Uninstall cancelled."
  )
}

@test "Removes completion files from fallback dirs when XDG_DATA_HOME is set" {
  (
    local temp_script_path="/tmp/memo"

    mkdir -p "$temp_script_path"
    touch "$temp_script_path/memo"

    local zsh_dir="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/site-functions"
    local fallback_bash="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions"

    mkdir -p "$zsh_dir" "$fallback_bash"
    touch "$zsh_dir/_memo" "$fallback_bash/memo"

    local sys_bash="/usr/local/share/bash-completion/completions"

    local test_sys_bash=false
    if [ -w "$(dirname "$sys_bash")" ]; then
      test_sys_bash=true
      mkdir -p "$sys_bash"
      touch "$sys_bash/memo"
    fi

    # shellcheck disable=SC2317,SC2329
    _resolve_script_path() { printf "%s\n" "$temp_script_path"; }

    run memo_uninstall <<<""
    assert_success
    assert_output --partial "Deleted completion files"

    refute [ -e "$zsh_dir/_memo" ]
    refute [ -e "$fallback_bash/memo" ]

    if [ "$test_sys_bash" = true ]; then
      refute [ -e "$sys_bash/memo" ]
    fi
  )
}

#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

teardown() {
  rm -rf "${NOTES_DIR:?}"/{,.}*
}

@test "grep should successfully find and edit a note" {

  # Create a mock encrypted cache file
  local file="$NOTES_DIR/file.md"
  echo "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  build_notes_cache

  # Mock fzf to return the selected line
  # shellcheck disable=SC2329
  fzf() {
    # Verify the input to fzf
    local fzf_input
    read -r -d '' fzf_input

    echo "$fzf_input"
  }

  # Mock edit_memo to verify it's called with the correct arguments
  # shellcheck disable=SC2329
  edit_memo() {
    if [[ "$1" == "$NOTES_DIR/file.md.gpg" ]]; then
      echo "edit_memo called with correct file"
    else
      echo "edit_memo called with wrong file" >&2
    fi
  }

  run grep ""

  assert_success
  assert_output "edit_memo called with correct file"
}

@test "grep should do nothing when no line is selected in fzf" {

  # Create a mock encrypted cache file
  local file="$NOTES_DIR/file.md"
  echo "Hello World" >"$file"

  gpg_encrypt "$file" "$file.gpg"

  build_notes_cache

  fzf() {
    echo ""
  }

  # Mock edit_memo to verify it's called with the correct arguments
  edit_memo() {
    echo "edit_memo was called unexpectedly" >&2
    return 1
  }

  run grep ""

  assert_success
  refute_output "edit_memo was called unexpectedly"
}

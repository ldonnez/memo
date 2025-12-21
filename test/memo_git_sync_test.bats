#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert
  TEST_TEMP_DIR="$(mktemp -d)"
  REMOTE_DIR="$TEST_TEMP_DIR/remote"
  git config --global init.defaultBranch main
  git init --bare -b main "$REMOTE_DIR"

  # Initialize Local, add a file, and link to remote
  git init -b main "$NOTES_DIR"
  git -C "$NOTES_DIR" config --global user.email "test@example.com"
  git -C "$NOTES_DIR" config --global user.name "Test User"
  git -C "$NOTES_DIR" config --global init.defaultBranch main
  git -C "$NOTES_DIR" remote add origin "$REMOTE_DIR"

  # Create an initial commit so 'main' exists
  touch "$NOTES_DIR"/initial.gpg
  git -C "$NOTES_DIR" add .
  git -C "$NOTES_DIR" commit -m "initial"
  git -C "$NOTES_DIR" push origin main

  # shellcheck source=memo.sh
  source "memo.sh"
}

teardown() {
  rm -rf "${NOTES_DIR:?}"/.*
  rm -rf "${NOTES_DIR:?}"/*
  rm -rf "$TEST_TEMP_DIR"
}

@test "Pushes new changes to remote" {
  # 1. Create a new "note"
  touch "$NOTES_DIR/note.md.gpg"

  # 2. Run the function
  run memo_git_sync
  assert_success
  assert_output --partial "Sync complete: Changes pushed."

  # Ensure commit exists on remote
  run git -C "$REMOTE_DIR" log --oneline
  assert_output --partial "$DEFAULT_GIT_COMMIT"
}

@test "Handles no changes" {
  run memo_git_sync
  assert_success
  assert_output --partial "Sync complete: No new commits needed."
}

@test "Fails if not a git repo" {
  rm -rf "$NOTES_DIR/.git"

  run memo_git_sync
  assert_failure
  assert_output "Not a git repository."
}

@test "Errors when conflict" {
  printf "initial" >"$NOTES_DIR/conflict.gpg"
  git -C "$NOTES_DIR" add conflict.gpg
  git -C "$NOTES_DIR" commit -m "initial commit"
  git -C "$NOTES_DIR" push origin main

  # Remote change via 'other machine'
  local other_dir="$TEST_TEMP_DIR/other_machine"
  git clone "$REMOTE_DIR" "$other_dir"
  printf "remote change" >"$other_dir/conflict.gpg"
  git -C "$other_dir" add conflict.gpg
  git -C "$other_dir" commit -m "remote change"
  git -C "$other_dir" push origin main

  # Local change
  printf "local change" >"$NOTES_DIR/conflict.gpg"

  run memo_git_sync
  assert_failure
  assert_output --partial "Error: Conflict detected during pull. Please resolve manually."
}

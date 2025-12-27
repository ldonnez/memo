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

  # shellcheck source=memo.sh
  source "memo.sh"
}

teardown() {
  rm -rf "${NOTES_DIR:?}"/.*
  rm -rf "${NOTES_DIR:?}"/*
  rm -rf "$TEST_TEMP_DIR"
}

@test "Initialized git" {
  run _is_git_repository
  assert_success
}

@test "Fails if not a git repo" {
  rm -rf "$NOTES_DIR/.git"

  run _is_git_repository 
  assert_failure
  assert_output "Not inside a git repository"
}

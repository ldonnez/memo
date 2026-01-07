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

@test "Initialized git" {
  run _git_init <<<"y"
  assert_success
  assert_output "This will initialize Git configuration for encrypted memo notes:
  - update .gitattributes
  - update local git config to ensure git diffs are readable
  - add a protective .gitignore (accident prevention)
Proceed? [y/N]: 
Added '*.gpg diff=gpg' to $NOTES_DIR/.gitattributes
Configured diff.gpg.textconv
Added '*' to $NOTES_DIR/.gitignore
Added '!*/' to $NOTES_DIR/.gitignore
Added '!**/*.gpg' to $NOTES_DIR/.gitignore
Added '!.gitignore' to $NOTES_DIR/.gitignore
Added '!.gitattributes' to $NOTES_DIR/.gitignore
Added '!.githooks/' to $NOTES_DIR/.gitignore"

  run _file_exists "$NOTES_DIR/.gitattributes"
  assert_success

  run _file_exists "$NOTES_DIR/.gitignore"
  assert_success

  run grep -qxF "*.gpg diff=gpg" "$NOTES_DIR/.gitattributes"
  assert_success

  run grep -qxF "*" "$NOTES_DIR/.gitignore"
  assert_success

  run grep -qxF "!*/" "$NOTES_DIR/.gitignore"
  assert_success

  run grep -qxF "!**/*.gpg" "$NOTES_DIR/.gitignore"
  assert_success

  run grep -qxF "!.gitattributes" "$NOTES_DIR/.gitignore"
  assert_success

  run grep -qxF "!.gitignore" "$NOTES_DIR/.gitignore"
  assert_success

  run grep -qxF "!.githooks/" "$NOTES_DIR/.gitignore"
  assert_success

}

@test "Aborts when pressing no" {
  run _git_init <<<"n"
  assert_success
  assert_output "This will initialize Git configuration for encrypted memo notes:
  - update .gitattributes
  - update local git config to ensure git diffs are readable
  - add a protective .gitignore (accident prevention)
Proceed? [y/N]: 
Aborted."
}

@test "Fails if not a git repo" {
  rm -rf "$NOTES_DIR/.git"

  run _git_init
  assert_failure
  assert_output "Not inside a git repository"
}

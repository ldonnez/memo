#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

teardown() {
  rm -f "$TEST_HOME/pass.txt"
  rm -rf "${NOTES_DIR:?}"/*
}

@test "feeds the passphrase on descriptor 3 and keeps it out of argv" {
  printf "secret passphrase" >"$TEST_HOME/pass.txt"
  MEMO_PASSPHRASE_FILE="$TEST_HOME/pass.txt"

  # shellcheck disable=SC2329
  gpg() {
    printf 'argv: %s\n' "$*"
    printf 'fd 3: %s' "$(cat <&3)"
  }

  run _gpg_run --decrypt some.gpg

  assert_success
  # The options come first, because gpg stops reading options at the file name.
  assert_output --partial "argv: --pinentry-mode loopback --passphrase-fd 3 --decrypt some.gpg"
  assert_output --partial "fd 3: secret passphrase"
  refute_line --partial "argv: *secret passphrase"
}

@test "leaves the passphrase options out when no source is configured" {
  # shellcheck disable=SC2329
  gpg() {
    printf 'argv: %s\n' "$*"
  }

  run _gpg_run --decrypt some.gpg

  assert_success
  assert_output "argv: --decrypt some.gpg"
  refute_output --partial "--passphrase-fd"
}

@test "does not run gpg when the passphrase cannot be resolved" {
  MEMO_PASSPHRASE_FILE="$TEST_HOME/does_not_exist.txt"

  # shellcheck disable=SC2329
  gpg() {
    printf 'gpg was called\n'
  }

  run _gpg_run --decrypt some.gpg

  assert_failure
  assert_output --partial "Passphrase file not found: $TEST_HOME/does_not_exist.txt"
  refute_output --partial "gpg was called"
}

@test "encrypts and decrypts a note with a passphrase file" {
  printf "secret passphrase" >"$TEST_HOME/pass.txt"
  MEMO_PASSPHRASE_FILE="$TEST_HOME/pass.txt"

  run _gpg_run --yes --armor -z 0 --compress-algo none --symmetric \
    -o "$NOTES_DIR/sym.md.gpg" <<<"Hello Symmetric"
  assert_success

  run _gpg_run --quiet --yes --decrypt "$NOTES_DIR/sym.md.gpg"
  assert_output "Hello Symmetric"
}

@test "reuses a descriptor passphrase across gpg runs" {
  printf "secret passphrase" >"$TEST_HOME/pass.txt"
  exec 7<"$TEST_HOME/pass.txt"
  MEMO_PASSPHRASE_FD=7

  # Called without `run`, which would run it in a subshell and throw the
  # remembered passphrase away again.
  _gpg_run --yes --armor -z 0 --compress-algo none --symmetric \
    -o "$NOTES_DIR/fd1.md.gpg" <<<"First note"
  _gpg_run --yes --armor -z 0 --compress-algo none --symmetric \
    -o "$NOTES_DIR/fd2.md.gpg" <<<"Second note"

  # The descriptor is empty by now, so this only works when the value read from
  # it is kept for the gpg runs that follow.
  run _gpg_run --quiet --yes --decrypt "$NOTES_DIR/fd1.md.gpg"
  assert_success
  assert_output "First note"

  run _gpg_run --quiet --yes --decrypt "$NOTES_DIR/fd2.md.gpg"
  assert_success
  assert_output "Second note"
}

@test "asks pinentry when no passphrase is configured" {
  printf "secret passphrase" >"$TEST_HOME/pass.txt"
  MEMO_PASSPHRASE_FILE="$TEST_HOME/pass.txt"

  run _gpg_run --yes --armor -z 0 --compress-algo none --symmetric \
    -o "$NOTES_DIR/asked.md.gpg" <<<"Hello Symmetric"
  assert_success

  # Without a passphrase source gpg falls back to pinentry, which the gpg-agent
  # from setup_suite answers with a failure. What matters here is that it fails
  # right away instead of waiting for somebody to type the passphrase.
  unset MEMO_PASSPHRASE_FILE

  run _gpg_run --quiet --yes --decrypt "$NOTES_DIR/asked.md.gpg"
  assert_failure
  refute_output --partial "Passphrase"
}

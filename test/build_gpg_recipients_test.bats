#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

teardown() {
  rm -rf "${NOTES_DIR:?}"/.*
  rm -rf "${NOTES_DIR:?}"/*
}

@test "builds single gpg recipient" {
  local gpg_recipients="$GPG_RECIPIENTS"
  local -a recipients=()

  _build_gpg_recipients "$gpg_recipients" recipients
  # capture return code
  local rc=$?

  assert_equal $rc 0
  assert_equal "${recipients[*]}" "-r mock@example.com"
}

@test "builds multiple gpg recipients" {
  gpg --batch --gen-key <<EOF
%no-protection
Key-Type: RSA
Key-Length: 1024
Name-Real: mock user2
Name-Email: test2@example.com
Expire-Date: 0
%commit
EOF
  # shellcheck disable=SC2030,SC2031
  local gpg_recipients="mock@example.com,test2@example.com"
  local -a recipients=()

  _build_gpg_recipients "$gpg_recipients" recipients
  # capture return code
  local rc=$?

  assert_equal $rc 0
  assert_equal "${recipients[*]}" "-r mock@example.com -r test2@example.com"
}

@test "sets --default-recipient-self when no gpg keys given" {
  local gpg_recipients=""
  local -a recipients=()

  _build_gpg_recipients "$gpg_recipients" recipients
  # capture return code
  local rc=$?

  assert_equal $rc 0
  assert_equal "${recipients[*]}" "--default-recipient-self"
}

@test "continues with found gpg keys when one of the gpg keys is not found" {
  local gpg_recipients="i-do-not-exist@example.com,mock@example.com,"
  local -a recipients=()

  _build_gpg_recipients "$gpg_recipients" recipients

  assert_equal "${recipients[*]}" "-r mock@example.com"
}

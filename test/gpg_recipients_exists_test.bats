#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

@test "returns 0 when 1 gpg key exists" {
  run _gpg_recipients_exists "$GPG_RECIPIENTS"
  assert_success
}

@test "returns 0 when given empty key id" {
  run _gpg_recipients_exists ""
  assert_success
}

@test "returns 1 when single gpg key does not exist" {
  run _gpg_recipients_exists "i-do-not-exist"
  assert_failure
  assert_output "GPG recipient(s) not found: i-do-not-exist"
}

@test "returns 0 when all gpg keys exist" {
  gpg --batch --gen-key <<EOF
%no-protection
Key-Type: RSA
Key-Length: 1024
Name-Real: mock2 user
Name-Email: mock2@example.com
Expire-Date: 0
%commit
EOF
  run _gpg_recipients_exists "$GPG_RECIPIENTS, mock2@example.com"
  assert_success
}

@test "returns 1 when 1 of the gpg keys does not exist" {
  run _gpg_recipients_exists "$GPG_RECIPIENTS, i-do-not-exist"
  assert_failure
  assert_output "GPG recipient(s) not found: i-do-not-exist"
}

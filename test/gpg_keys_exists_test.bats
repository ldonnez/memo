#!/usr/bin/env bats

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

@test "returns 0 when 1 gpg key exists" {
  run gpg_keys_exists "$KEY_IDS"
  assert_success
}

@test "returns 1 when single gpg key does not exist" {
  run gpg_keys_exists "i-do-not-exist"
  assert_failure
  assert_output "GPG key(s) not found: i-do-not-exist"
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
  run gpg_keys_exists "$KEY_IDS, mock2@example.com"
  assert_success
}

@test "returns 1 when 1 of the gpg keys does not exist" {
  run gpg_keys_exists "$KEY_IDS, i-do-not-exist"
  assert_failure
  assert_output "GPG key(s) not found: i-do-not-exist"
}

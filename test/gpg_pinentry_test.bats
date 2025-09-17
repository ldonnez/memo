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

@test "_gpg_pinentry succeeds when cache not needed (no secret key)" {
  run _gpg_pinentry
  assert_success
}

@test "_gpg_pinentry asks for password when not cached" {
  gpg --batch --gen-key <<EOF
Key-Type: RSA
Key-Length: 1024
Name-Real: example user
Name-Email: password@example.com
Passphrase: testpass
Expire-Date: 0
%commit
EOF

  GPG_PASSPHRASE="testpass" run _gpg_pinentry "password@example.com"
  assert_output "Passphrase not cached — prompting..."
}

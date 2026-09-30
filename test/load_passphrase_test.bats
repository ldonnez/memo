#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031 # every bats test runs in a subshell of its own

setup() {
  bats_load_library bats-support
  bats_load_library bats-assert

  # shellcheck source=memo.sh
  source "memo.sh"
}

teardown() {
  rm -f "$TEST_HOME/pass.txt"
}

@test "leaves the passphrase empty when no source is configured" {
  _load_passphrase

  assert_equal "" "$_MEMO_PASSPHRASE"

  run _has_passphrase_source
  assert_failure
}

@test "reads the passphrase from a file" {
  printf "from a file" >"$TEST_HOME/pass.txt"
  MEMO_PASSPHRASE_FILE="$TEST_HOME/pass.txt"

  _load_passphrase

  assert_equal "from a file" "$_MEMO_PASSPHRASE"
}

@test "reads only the first line of a passphrase file" {
  printf "the first line\nthe second line\n" >"$TEST_HOME/pass.txt"
  MEMO_PASSPHRASE_FILE="$TEST_HOME/pass.txt"

  _load_passphrase

  assert_equal "the first line" "$_MEMO_PASSPHRASE"
}

@test "reads a passphrase file without a trailing newline" {
  printf "no newline" >"$TEST_HOME/pass.txt"
  MEMO_PASSPHRASE_FILE="$TEST_HOME/pass.txt"

  _load_passphrase

  assert_equal "no newline" "$_MEMO_PASSPHRASE"
}

@test "fails when the passphrase file does not exist" {
  MEMO_PASSPHRASE_FILE="$TEST_HOME/does_not_exist.txt"

  run _load_passphrase
  assert_failure
  assert_output --partial "Passphrase file not found: $TEST_HOME/does_not_exist.txt"
}

@test "reads the passphrase from a descriptor" {
  printf "from a descriptor" >"$TEST_HOME/pass.txt"
  exec 7<"$TEST_HOME/pass.txt"
  MEMO_PASSPHRASE_FD=7

  _load_passphrase

  assert_equal "from a descriptor" "$_MEMO_PASSPHRASE"
}

@test "keeps a descriptor passphrase for the calls that follow" {
  printf "from a descriptor" >"$TEST_HOME/pass.txt"
  exec 7<"$TEST_HOME/pass.txt"
  MEMO_PASSPHRASE_FD=7

  _load_passphrase
  assert_equal "from a descriptor" "$_MEMO_PASSPHRASE"

  # A descriptor is drained by the first read, so the second call has to answer
  # from the remembered value instead of reading the descriptor again.
  _load_passphrase
  assert_equal "from a descriptor" "$_MEMO_PASSPHRASE"
}

@test "reads the passphrase from the environment variable it names" {
  export MEMO_TEST_PASSPHRASE="from the environment"
  MEMO_PASSPHRASE_ENV=MEMO_TEST_PASSPHRASE

  _load_passphrase

  assert_equal "from the environment" "$_MEMO_PASSPHRASE"
}

@test "fails when the named environment variable is not set" {
  unset MEMO_TEST_PASSPHRASE
  MEMO_PASSPHRASE_ENV=MEMO_TEST_PASSPHRASE

  run _load_passphrase
  assert_failure
  assert_output --partial "Passphrase environment variable not set: MEMO_TEST_PASSPHRASE"
}

@test "fails when the named environment variable is empty" {
  export MEMO_TEST_PASSPHRASE=""
  MEMO_PASSPHRASE_ENV=MEMO_TEST_PASSPHRASE

  run _load_passphrase
  assert_failure
  assert_output --partial "Passphrase environment variable not set: MEMO_TEST_PASSPHRASE"
}

@test "fails instead of asking pinentry when the passphrase is empty" {
  printf "\n" >"$TEST_HOME/pass.txt"
  MEMO_PASSPHRASE_FILE="$TEST_HOME/pass.txt"

  run _load_passphrase
  assert_failure
  assert_output --partial "Passphrase is empty"
}

@test "prefers the file over the descriptor and the environment" {
  printf "from the file" >"$TEST_HOME/pass.txt"
  exec 7<"$TEST_HOME/pass.txt"
  export MEMO_TEST_PASSPHRASE="from the environment"

  MEMO_PASSPHRASE_ENV=MEMO_TEST_PASSPHRASE
  MEMO_PASSPHRASE_FD=7
  MEMO_PASSPHRASE_FILE="$TEST_HOME/pass.txt"

  _load_passphrase

  assert_equal "from the file" "$_MEMO_PASSPHRASE"
}

@test "prefers the descriptor over the environment" {
  printf "from the descriptor" >"$TEST_HOME/pass.txt"
  exec 7<"$TEST_HOME/pass.txt"
  export MEMO_TEST_PASSPHRASE="from the environment"

  MEMO_PASSPHRASE_ENV=MEMO_TEST_PASSPHRASE
  MEMO_PASSPHRASE_FD=7

  _load_passphrase

  assert_equal "from the descriptor" "$_MEMO_PASSPHRASE"
}

@test "resolves again when the configured source changes" {
  printf "from the file" >"$TEST_HOME/pass.txt"
  MEMO_PASSPHRASE_FILE="$TEST_HOME/pass.txt"

  _load_passphrase
  assert_equal "from the file" "$_MEMO_PASSPHRASE"

  # A different source is resolved, instead of the old value being reused.
  export MEMO_TEST_PASSPHRASE="from the environment"
  MEMO_PASSPHRASE_ENV=MEMO_TEST_PASSPHRASE
  unset MEMO_PASSPHRASE_FILE

  _load_passphrase
  assert_equal "from the environment" "$_MEMO_PASSPHRASE"

  # And with every source gone, pinentry is left to ask.
  unset MEMO_PASSPHRASE_ENV

  _load_passphrase
  assert_equal "" "$_MEMO_PASSPHRASE"
}

@test "keeps the passphrase out of the environment" {
  printf "from a file" >"$TEST_HOME/pass.txt"
  MEMO_PASSPHRASE_FILE="$TEST_HOME/pass.txt"

  _load_passphrase

  run bash -c 'printf "%s" "${_MEMO_PASSPHRASE-}"'
  assert_output ""
}

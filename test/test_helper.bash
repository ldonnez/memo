make_encrypted_file() {
  local content="$1"
  local output_path="$2"

  printf "%s" "$content" | gpg --encrypt --recipient "$KEY_IDS" --output "$output_path" >/dev/null 2>&1
}

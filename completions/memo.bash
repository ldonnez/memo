# bash completion for memo
#
# Install as /usr/local/share/bash-completion/completions/memo (or into your
# BASH_COMPLETION_USER_DIR) and restart your shell.

# Resolves NOTES_DIR from the memo config file (see memo.sh), defaulting to
# $HOME/notes. Runs in a subshell so sourcing the config cannot affect the
# interactive shell.
_memo_get_notes_dir() {
  local notes_dir
  notes_dir=$(
    if [[ -f "${XDG_CONFIG_HOME:-$HOME/.config}/memo/config" ]]; then
      # shellcheck source=/dev/null
      source "${XDG_CONFIG_HOME:-$HOME/.config}/memo/config"
      printf '%s' "${NOTES_DIR:-$HOME/notes}"
    else
      printf '%s' "$HOME/notes"
    fi
  ) 2>/dev/null || true
  printf '%s' "${notes_dir:-$HOME/notes}"
}

_memo() {
  local cur
  cur="${COMP_WORDS[COMP_CWORD]}"

  local commands="help encrypt decrypt encrypt-files decrypt-files files integrity-check sync init upgrade uninstall version today yesterday tomorrow"

  if ((COMP_CWORD == 1)); then
    local -a candidates=()
    local c
    while IFS= read -r c; do
      candidates+=("$c")
    done < <(compgen -W "$commands" -- "$cur")
    COMPREPLY=("${candidates[@]}")
    return
  fi

  local notes_dir
  notes_dir=$(_memo_get_notes_dir)

  local -a candidates=()
  local c
  case "${COMP_WORDS[1]}" in
  encrypt)
    while IFS= read -r c; do
      candidates+=("$c")
    done < <({
      compgen -W "--symmetric --passphrase-fd --passphrase-file --passphrase-env" -- "$cur"
      compgen -f -- "$cur"
    })
    ;;
  decrypt)
    while IFS= read -r c; do
      candidates+=("$c")
    done < <({
      compgen -W "--passphrase-fd --passphrase-file --passphrase-env" -- "$cur"
      cd "$notes_dir" 2>/dev/null && compgen -f -X '!*.gpg' -- "$cur"
      cd "$notes_dir" 2>/dev/null && compgen -f -X '!*.asc' -- "$cur"
    })
    ;;
  decrypt-files)
    while IFS= read -r c; do
      candidates+=("$c")
    done < <({
      compgen -W "all --passphrase-fd --passphrase-file --passphrase-env" -- "$cur"
      cd "$notes_dir" 2>/dev/null && compgen -f -X '!*.gpg' -- "$cur"
      cd "$notes_dir" 2>/dev/null && compgen -f -X '!*.asc' -- "$cur"
    })
    ;;
  encrypt-files)
    while IFS= read -r c; do
      candidates+=("$c")
    done < <({
      compgen -W "all --dry-run --exclude --symmetric --passphrase-fd --passphrase-file --passphrase-env" -- "$cur"
      cd "$notes_dir" 2>/dev/null && compgen -f -- "$cur"
    })

    # Notes are encrypted already, so only plaintext files can be encrypted.
    # Filtered here instead of with -X, since compgen honors just the last one.
    local -a plaintext=()
    if ((${#candidates[@]} > 0)); then
      while IFS= read -r c; do
        [[ "$c" == *.asc || "$c" == *.gpg ]] || plaintext+=("$c")
      done < <(printf '%s\n' "${candidates[@]}")
    fi
    candidates=("${plaintext[@]}")
    ;;
  sync | init)
    if ((COMP_CWORD == 2)); then
      while IFS= read -r c; do
        candidates+=("$c")
      done < <(compgen -W "git" -- "$cur")
    fi
    ;;
  upgrade)
    while IFS= read -r c; do
      candidates+=("$c")
    done < <(compgen -W "-f --force" -- "$cur")
    ;;
  esac

  if ((${#candidates[@]} > 0)); then
    COMPREPLY=("${candidates[@]}")
  fi
}

complete -F _memo memo

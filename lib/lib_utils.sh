



# UI libs
# =================

# Ask the user to confirm
_confirm() {
  local msg="Do you want to continue?"
  >&2 printf "%s" "${1:-$msg}"
  >&2 printf "%s" "([y]es or [N]o): "
  export REPLY=

  >&2 read -r REPLY
  case $(tr '[A-Z]' '[a-z]' <<<"$REPLY") in
  y | yes)
    # printf "%s\n" "true"
    return 0
    ;;
  *)
    # printf "%s\n" "false"
    return 1
    ;;
  esac
}

# Ask the user to input string
_input() {
  local msg="Please enter input:"
  local default=${2-}
  >&2 printf "%s" "${1:-$msg}${default:+ [$default]}: "
  >&2 read -r REPLY
  [[ -n "$REPLY" ]] || REPLY=${default}
  printf "%s\n" "$REPLY"
}

# Ask the user to input string
_input2() {
  local default=${1-}
  local msg=${2:-"Please enter input"}
  local status=true
  export REPLY=

  while $status; do
    >&2 printf "%s" "${msg}${default:+ [$default]}: "
    >&2 read -r REPLY
    [[ -n "$REPLY" ]] || REPLY=${default}
    status=false
  done

  # printf "%s\n" "$REPLY"
}

_input_pass() {
  local msg=${1:-"Please enter password"}
  local status=true
  export REPLY=

  while $status; do
    >&2 printf "%s" "${msg}: "
    >&2 read -s -r REPLY

    >&2 echo ""
    if [[ -z "$REPLY" ]]; then
      _log WARN "Empty password, please try again."
    else
      status=false
    fi
  done

}

# Transform yaml to json
_yaml2json() {
  python3 -c 'import json, sys, yaml ; y = yaml.safe_load(sys.stdin.read()) ; print(json.dumps(y))'
}



# Low level helpers
# =================

# Ensure a directory exists
ensure_dir() {
  local target=$1

  [[ -d "$target" ]] || _exec mkdir -p "$target"

}

# Return relative path from project root
make_rel_path_from_root() {
  sed -E "s:^$PROJECT_ROOT/?::"
}

# VALIDATED
# Return hash of string
hash_sum() {
  local seed=$1
  if [[ "$seed" == '-' ]]; then
    sha256sum - | sed 's/ .*//'
  else
    echo -n "$seed" | sha256sum | sed 's/ .*//'
  fi

}

# Ensure a config is correctly patched
patch_file() {
  local file="$1"
  local key_name="$2"
  local content
  local delim_key=ssh_config
  content=$(cat -)

  # Prepare delimiters
  local start_delimiter="# --- Start: $APP_NAME $delim_key $key_name ---"
  local stop_delimiter="# --- Stop: $APP_NAME $delim_key $key_name ---"

  # Ensure destination exists
  if [[ ! -f "$file" ]]; then

    local parent=$(dirname "${file}")
    if [[ -z "$parent" ]] && [[ ! -d "$parent" ]]; then
      _log INFO "Create missing parent directory: $parent"
      ensure_dir "$parent"
    fi

    _log INFO "Create new empty file: $file"
    _exec touch "$file"
  fi

  # Create payload
  local payload="$start_delimiter
$content
$stop_delimiter"

  if grep -q "$start_delimiter" "$file" && grep -q "$stop_delimiter" "$file"; then

    # Delimiters exist, check if update is needed
    local current_content='' content_before='' content_after=''

    # Calculate line indexes
    local line_sof=1
    local line_start=$(grep -n "$start_delimiter" "$file" | cut -f1 -d: | head -n 1)
    local line_stop=$(grep -n "$stop_delimiter" "$file" | cut -f1 -d: | head -n 1)
    local line_eof=$(wc -l "$file" | cut -d' ' -f1)

    line_stop=$((line_stop + 1))
    current_content=$(sed -n "${line_start},${line_stop}p;" "$file")

    _log TRACE "Line separators: $line_sof -> $line_start -> $line_stop -> $line_eof"

    if [ "$current_content" != "$payload" ]; then
      # Update needed
      _log INFO "Update content of: $file"

      # Update content
      if ! $APP_DRY; then
        (
          if [[ "$line_start" -gt 1 ]]; then
            sed -n "1,${line_start}p;" "$file" | sed '$ d'
          fi
          echo "$payload"
          if [[ "$line_stop" -lt $line_eof ]]; then
            sed -n "${line_stop},\$p" "$file" #| sed '1 d'
          fi
        ) >"$file.tmp"
        mv "$file.tmp" "$file"
      else
        _log DRY "Update file: $file"
      fi

    else
      _log INFO "File '$file' is already correctly configured"
    fi
    set +x
  else

    # TOFIX: Insert before Host *
    # local line_start=$(grep -n "Host *" "$file" | cut -f1 -d: | head -n 1)

    # Delimiters don't exist, append to the end of the file
    _log INFO "Add to content to: $file"
    if ! $APP_DRY; then
      echo -e "\n$payload" >>"$file"
    else
      _log DRY "Update file: $file"
    fi
  fi
}



# Git commands
# =====================

is_in_git() {
  local file=$1
  if git status --porcelain "$file" | grep -q '^?? '; then
    return 1
  fi
  return 0
}

is_in_git_clean_stage() {
  local file=$1
  local ret=$(git status --porcelain "$file")
  if [[ -z "$ret" ]]; then
    return 0
  elif grep -q '^A ' <<<"$ret"; then
    return 0
  fi
  return 1
}

ensure_file_in_git() {
  local file=$1

  if is_in_git_clean_stage "$file"; then
    _log DEBUG "File is already in git"
  else
    _log DEBUG "Add encrypted file into git"
    _exec git add "$file"
  fi
}

# Return true if local and remote branch have diverged
_is_git_diverged ()
{
  local banch_name=${1:-main}
  local count=$(git show-ref $banch_name | awk '{print $1}' | sort -u | wc -l)

  if [[ "$count" -eq 1 ]]; then
    return 1
  elif [[ "$count" -eq 2 ]]; then
    return 0
  else
    return 2
  fi
}


# Age commands
# =====================

# Return true if age encrypted
is_age_encrypted_file() {
  local file=$1
  local ret=1

  [[ -f "$file" ]] || return 1

  if grep -q "BEGIN AGE ENCRYPTED FILE-----" "$file"; then
    ret=0
  elif grep -q "age-encryption.org/v1" "$file"; then
    ret=0
  fi

  return $ret
}

# Passwordless decrypt
_age_decrypt_with_ident() {
  cb_init_ident_pass || return $?

  [[ -n "$APP_IDENT_PRIV_KEY" ]] || _die 1 "Missing ident private key"
  _log DEBUG "Decrypt with age and internal priv key"
  age --decrypt \
    --identity <(echo "$APP_IDENT_PRIV_KEY") "$@"

  return $?

}

# Encrypt a file with age
_age_encrypt_file() {
  local file=$1
  local recipient=$2

  local dest=${3:-$file}

  # shellcheck disable=SC2086
  cat "$file" | age --encrypt \
    --armor \
    --recipient ${recipient//,/ --recipient } \
    -o "$dest"
}

# Decrypt a file with age
_age_decrypt_file() {
  local file=$1
  local ident=$2
  local dest=${3:-$file}

  # cb_init_ident "$ident"

  ident=${ident:-$APP_USER_IDENTITY_CRYPT_TARGET}

  _exec _age_decrypt_with_ident -o "$dest" "$file"
}

_age_public_key_from_private_key() {
  local file=$1
  local priv_key='' pub_key=''

  priv_key=$(age --decrypt "$file" 2>/dev/null)
  echo "$priv_key" | age-keygen -y

}

# Transform a list of recipients in age args
_age_build_recipients_args() {
  local pub_keys=$@
  local ret=

  pub_keys=$(tr '\n' ' ' <<<"$pub_keys")
  for recipient in $pub_keys; do
    ret="${ret:+$ret }-r $recipient"
  done
  [[ -n "$ret" ]] || return 1
  printf "%s" "$ret"
}

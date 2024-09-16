


# Internal helpers
# =================

make_default_ident() {
  local name=$1
  [[ -f "$APP_USER_IDENTITY_FILE" ]] || {
    _die 1 "No such identiry: $name"
  }
  echo "$name" >"$APP_CURR_ID_FILE"
}

assert_current_ident() {
  [[ -n "$APP_CURR_IDENT" ]] || _die 1 "You must setup an ident first"
}

lib_keyring_is_unlocked() {
  local closed=

  if ! command -v "secret-tool" &>/dev/null; then
    _log DEBUG "Keyring disabled: Missing 'secret-tool' command"
    return 1
  fi

  if command -v "busctl" &>/dev/null; then
    closed=$(
      busctl --user get-property org.freedesktop.secrets \
        /org/freedesktop/secrets/collection/login \
        org.freedesktop.Secret.Collection Locked |
        grep -o 'true\|false'
    )
  elif command -v "gdbus" &>/dev/null; then
    closed=$(
      gdbus call -e -d org.freedesktop.secrets \
        -o /org/freedesktop/secrets/collection/login \
        -m org.freedesktop.DBus.Properties.Get \
        org.freedesktop.Secret.Collection Locked |
        grep -o 'true\|false'
    )
  else
    _log INFO "Please install 'busctl' or 'gdbus' to query state of keyring"
    closed=false
  fi

  if [[ "$closed" == "false" ]]; then
    _log DEBUG "Keyring is available and open"
    return 0
  fi

  _log DEBUG "Keyring is not open"
  return 1
}

keyring_get_best_secret() {
  local ident=$1
  local live_secret=

  lib_keyring_is_unlocked || return 0

  if [[ "$APP_IDENT_FILE_STATUS" == "encrypted" ]]; then
    _log INFO "Using keyring password for ident: $ident"
    secret-tool lookup "${APP_NAME}-ident" "$ident" 2>/dev/null || true
  fi

}

ensure_file_encrypted() {
  local file=$1
  local recipient_name=${2:-$APP_CURR_IDENT}
  local recipient=$(get_recipiant_id "$recipient_name")

  if is_age_encrypted_file "$file"; then
    _log DEBUG "File is already encrypted"
  else
    _log INFO "Encrypt file: $file for $recipient_name"
    _exec _age_encrypt_file "$file" "$recipient"
  fi

}

ensure_file_in_gitattr() {
  local name=$1
  local suffix="filter=sops"
  local pattern="$name $suffix"
  if grep -q "^$pattern" "$APP_GITATTR_FILE" 2>/dev/null; then
    _log DEBUG "File is already in $APP_GITATTR_FILE"
    return 0
  fi
  _log INFO "Add file to .gitattributes: $file"

  if ${APP_DRY:-false}; then
    _log DRY "Update file: $APP_GITATTR_FILE"
  else
    _log INFO "Update file: $APP_GITATTR_FILE"
    echo "$pattern" >>"$APP_GITATTR_FILE"
  fi
}








# Directory management
# =================

lib_dir_add_ident() {
  _dir_db

}

# Return all age pubkeys
lib_dir_age_pubkeys() {
  _dir_db dump ident | grep age-pub= | sed -E 's/[a-zA-Z0-9\.-]*=//'
}

# Identity management (internal)
# =================

get_recipiant_id() {
  local name=$1

  local dest_inv="${APP_INV_DIR}/$name.pub"
  cat "$dest_inv"
}

get_id_file_of_ident() {
  local ident=$1

  local hash=
  hash=$(_dir_db get "ident.$ident.ident-hash")

  echo "$APP_IDENT_DIR/$hash.age"
}

# Load dump into shell
lib_id_as_vars() {
  # Reset env
  # shellcheck disable=SC2086
  unset ${!db_ident__*} || true

  # Load
  local db_exc=$(lib_id_dump | _db_to_vars)
  echo "$db_exc"
  eval "${db_exc}"

}

# Return all ident pub keys from directory
lib_id_get_all_pub_keys() {
  _dir_db dump |
    grep '^ident\.[a-zA-Z-]*\.age-pub=' |
    sed 's/.*=//'
}

# VALIDATED
# Dump all idents
lib_id_dump() {
  _dir_db dump | grep '^ident\.'
}

# VALIDATED
# List identities
lib_id_list() {
  lib_id_dump |
    grep 'email\|login' |
    sed 's/^ident\.//;s/\..*//' |
    sort -u
}

# VALIDATED
# Check if ident exists
lib_id_exists() {
  local id=$1
  grep -q "$id" <<<"$(lib_id_list)"
}

# Identity management (Public)
# =================

# VALIDATED
# Generate new encrypted id
lib_id_new_ident__age() {
  local ident=$1
  local priv_key= pub_key=

  # Ensure id does not already exists in config
  if lib_id_exists "$ident"; then
    _die 0 "Identity '$ident' already exists."
  fi

  # Load ident settings
  cb_init_ident "$ident"

  # Check if destinayion already exists
  if [[ -f "$APP_IDENT_FILE_ENC" ]]; then
    _log INFO "A age secret ident file is already present in: $APP_IDENT_FILE_ENC"
    $APP_FORCE ||
      _confirm "Do you really want to override '${APP_IDENT_NAME}' existing identity ?" ||
      _die 1 "User aborted"
  fi

  # Create identity
  _log INFO "Create new age id: $APP_IDENT_NAME"
  priv_key="$(age-keygen)"

  # Save into dedicated file
  ensure_dir "$APP_IDENT_DIR"
  pub_key=$(echo "$priv_key" | age-keygen -y)
  if ! $APP_DRY; then
    echo "$priv_key" | age --passphrase -a >"$APP_IDENT_FILE_ENC"
  else
    _log DRY "Save generated keypair in: $APP_IDENT_FILE_ENC"
  fi

  # Save in DB
  _dir_db set "ident.$APP_IDENT_NAME.ident-hash" "$APP_IDENT_HASH"
  _dir_db set "ident.$APP_IDENT_NAME.age-pub" "$pub_key"

  _log INFO "New private encrypted identity file: $APP_IDENT_FILE_ENC"
}

# Remove identity
lib_id_rm_ident__age() {
  local ident=$1
  local changed=false

  cb_init_ident "$ident"

  # Ensure id does exists in config
  if lib_id_exists "$APP_IDENT_NAME"; then
    $APP_FORCE ||
      _confirm "Do you really want to remove '${APP_IDENT_NAME}' identity ?" ||
      _die 1 "User aborted"
    changed=true
  fi

  # Look for key to remove
  _dir_db rms "ident.$APP_IDENT_NAME" --remove-section

  # Delete identification key
  for file in "$APP_IDENT_FILE_ENC" "$APP_IDENT_FILE_CLEAR"; do
    [[ ! -f "$file" ]] || {
      _log INFO "Remove identiry file: $file"
      _exec rm "$file"
      changed=true
    }
  done

  if $changed; then
    _log INFO "Identity '$APP_IDENT_NAME' has been removed"
  else
    _log INFO "Identity '$APP_IDENT_NAME' is already absent"
  fi
}




# CLI Ident Commands
# =================

# Display help message
cli__id_usage() {
  cat <<EOF
${APP_NAME}: Manage ids (Subcommand example)

usage: ${APP_NAME} id [OPTS] add NAME
       ${APP_NAME} id [OPTS] rm NAME
       ${APP_NAME} id [OPTS] ls NAME
       ${APP_NAME} id help
EOF
}

# Read CLI options, shows id level options
cli__id_options() {
  while [[ -n "${1:-}" ]]; do
    # : "parse-opt-start"
    case "$1" in
    -h | --help | help)
      : ",Show help"
      clish_help cli__id
      _die 0
      ;;
    -a | --all)
      : ",Select all"
      mode=all
      shift
      ;;
    -m | --message)
      : "MSG,Define message"
      [[ -n "${2:-}" ]] || _die 1 "Missing message"
      msg=$2
      shift 2
      ;;
    -*)
      _die 1 "Unknown option: $1"
      ;;
    *)
      args=("$@")
      shift $#
      ;;
    esac
    # : "parse-opt-stop"
  done
}

cli__id() {
  : "COMMAND,Manage ids"

  # Set default vars
  local msg="Default message"
  local mode="limited"
  local args=

  # Parse args
  clish_parse_opts cli__id "$@"
  set -- "${args[@]}"

  _db_ensure_open

  # Dispatch to sub commands
  clish_dispatch cli__id__ "$@" || _die $?
}

# Basic simple level sub-commands
# ---------------
cli__id__new() {
  : "NAME,Add new identity"
  local ident_=${1:-}
  local ident=''
  local email=''

  # Validate ident
  while [[ -z "$ident" ]]; do
    _input2 "${ident:-$ident_}" "Name of the new ident"
    ident=$REPLY
    if lib_id_exists "$ident"; then
      _log WARN "This id already exists, please choose another one."
      ident=
    fi
  done

  # Ask for email
  _input2 "$ident@$(hostname -f)" "Email"
  email=$REPLY

  # Create new ident
  lib_id_new_ident__age "$ident"

  # Set ident informations
  _dir_db set "ident.$ident.login" "$ident_"
  _dir_db set "ident.$ident.email" "$email"

  # Create user vault
  lib_vault_new "ident_${ident}" "$ident"

}

cli__id__ls() {
  : "NAME,List idents"

  lib_id_list

}

cli__id__keypair() {
  : "NAME,Show identity key pair (require unlock password)"
  cb_init_ident "$1"
  cb_init_ident_pass

  echo "ident: $APP_IDENT_NAME"
  echo "ident: $APP_IDENT_HASH"
  echo "public: $APP_IDENT_PUB_KEY"
  echo "private: $APP_IDENT_PRIV_KEY"
}

cli__id__rm() {
  : "NAME,Remove identiry"
  lib_id_rm_ident__age "$1"
}

cli__id__keyring() {
  : "IDENT,Set ident in local keyring"
  local ident=$1
  cb_init_ident "$1"
  cb_init_ident_pass

  # Store in keyring
  printf "%s" "$APP_IDENT_PRIV_KEY" |
    secret-tool store \
      --label="SecretMgr Ident - $ident" \
      application "$APP_NAME" \
      "${APP_NAME}-ident" "$ident"

  _log INFO "Identity has been added to keyring"
}



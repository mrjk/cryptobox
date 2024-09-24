
# Item management (internal)
# =================

# Start a hook
item_hook() {
  
  local _VAULT_KIND=$1
  local cmd=$2
  shift 2 || true

  [ -n "$cmd" ] || _die 3 "Missing _VAULT_KIND name, this is a bug"
  local fn_name="lib_${_VAULT_KIND}_hook__${cmd}"
  if [[ $(type -t "${fn_name}") == function ]]; then
    _log DEBUG "Executing hook: $fn_name for ${_VAULT_NAME:-}"
    "${fn_name}" "$@"
    return $?
  fi
}



# DEPRECATED
# =================


# Get item name from hash
# item_name_from_hash() {
#   local needle=$1
#   local kinds=${2:-$APP_ITEMS_KINDS}

#   for _VAULT_KIND in $kinds; do
    
#     _dir_db dump "$_VAULT_KIND." |
#       grep "store-hash=$needle$" |
#       sed 's/^'"$_VAULT_KIND"'.//;s/\..*//' |
#       sort -u
#   done
# }

## Multi _VAULT_KIND functions
#  ------
APP_ITEMS_KINDS=""

ident_vault_list ()
{
  local ident=$1

  _dir_db dump \
    | grep "\.shared=true\|\.recipient=$ident" \
    | cut -d'.' -f2 \
    | sort
}


## Per _VAULT_KIND functions
#  ------

# Return item's _VAULT_KIND
item_kind (){
  local ident=$1
  _dir_db dump |
    grep "\.$ident\." |
    cut -d'.' -f1 |
    sort -u |
    head -n 1
}

# List related resources for ident
item_ident_resources() {
  local ident=$1
  local kinds=${2:-$APP_ITEMS_KINDS}

  for kind in ${kinds//,/ }; do
    
    _dir_db dump "$kind." |
      grep "shared=true\|=$ident$" |
      cut -d'.' -f 2 |
      sort -u
  done
}


# List all resources
item_list_names2() {
  _dir_db dump "vault" |
    cut -d '.' -f 2 |
    sort -u
}

item_list_names_flat (){
  item_list_names2 | tr '\n' ' ' | sed 's/,$//'
}

# Check if a given NAME resource exist
item_assert_exists2() {
  local name=$1

  if item_list_names2 | grep -q "^$name$"; then
    _log TRACE "Vault name '$name' exists"
    return 0
  fi

  _log TRACE "Vault name '$name' does not exists"
  return 1
}


# Return all recipients ids for a given vault, comma seprated
item_recipient_idents2() {
  local name=$1
  local shared=$(_dir_db get "vault.$name.shared" 2>/dev/null || echo false)

  # Generate recipient list
  if [[ "$shared" == 'true' ]]; then
    lib_id_list
  else
    _dir_db get "vault.$name.recipient" |
      sort -u
  fi
}

# Return age pub_keys from recipients
item_recipient_idents_age_args() {
  local idents=$1

  local ret=
  for ident in ${idents//,/ }; do
    match=$(_dir_db get "ident.$ident.age-pub")
    if [[ -n "$match" ]]; then
      ret="${ret:+$ret }$match"
    else
      _log WARN "Impossible to get public key of ident: $ident"
    fi
  done

  [[ -n "$ret" ]] || return 1
  _age_build_recipients_args "$ret"
}






# Item loaders
# =================

item_load_new () {
  local vault_name=$1

  # Assert item does NOT exists
  if item_assert_exists2 "$vault_name"; then
    _log ERROR "Vault '$vault_name' already exists DEBUG"
    return 1
  fi

  export _VAULT_NAME=$vault_name
  export _VAULT_KIND="vault"
  export _VAULT_HASH=$(hash_sum "$_VAULT_NAME")
  export _VAULT_ENC="$APP_STORES_DIR/$_VAULT_HASH.age"
  export _VAULT_DIR="$APP_VAULTS_DIR/$_VAULT_NAME"

}


# New version, without kind
item_load_existing () {
  local vault_name=$1
  # Assert item exists
  [[ -n "$vault_name" ]]|| {
    _log HINT "Missing vault argument, please check usage"
    _log ERROR "Empty vault name, please choose one of: $(item_list_names_flat)"
    return 1
  }

  # Assert DB is open
  _db_is_open || {
    _log ERROR "You must unlock the cryptobox first"
    return 1
  }

  # Assert item exists
  item_assert_exists2 "$vault_name" || {
    _log ERROR "Vault '$vault_name' not found in config, please choose one of: $(item_list_names_flat)"
    return 1
  }

  export _VAULT_NAME=$vault_name
  export _VAULT_KIND=$(item_kind "$_VAULT_NAME")

  export _VAULT_HASH=$(_dir_db get "$_VAULT_KIND.$_VAULT_NAME.store-hash" ) #2>/dev/null) # vault_hash
  export _VAULT_ENC="$APP_STORES_DIR/$_VAULT_HASH.age" # vault_enc
  export _VAULT_DIR="$APP_VAULTS_DIR/$_VAULT_NAME" # _VAULT_DIR

  # Load hooks: load
  item_hook "$_VAULT_KIND" load \
    || {
      _log ERROR "Failed hook: load for $_VAULT_KIND"
      return 1 
    }

}


item_unload () {
  unset ${!_VAULT_*}
}



# Initial  config
# =================

# Create a new init config
item_new_config (){
  export _VAULT_NAME=${1:-CRYPTOBOX}
  export _VAULT_KIND="vault"
  export _VAULT_HASH=$(hash_sum "$_VAULT_NAME")
  export _VAULT_ENC="$APP_STORES_DIR/$_VAULT_HASH.age"
  export _VAULT_DIR="$APP_VAULTS_DIR/$_VAULT_NAME"

  item_hook "$_VAULT_KIND" new_pre \
    || {
      _log ERROR "Failed hook: new_pre for $_VAULT_KIND"
      return 1
    }

  item_hook "$_VAULT_KIND" new_post \
    || {
      _log ERROR "Failed hook: new_post for $_VAULT_KIND"
      return 1 
    }


  # Prepare DB
  _db_ensure_created "$_VAULT_DIR/cryptobox.ini"
  _dir_db set "$_VAULT_KIND.$_VAULT_NAME.internal" "true"
  _dir_db set "$_VAULT_KIND.$_VAULT_NAME.shared" "true"
  _dir_db set "$_VAULT_KIND.$_VAULT_NAME.store-hash" "$_VAULT_HASH"

}



# Item API
# =================


# Create a new item in config
item_new() {

  # Assert DB is open
  _db_is_open || _die 1 "You must unlock the cryptobox first"

  item_load_new "$1" || return $?; shift 1
  local idents=${@:-}
  local valid=false

  # HOOK: ${_VAULT_KIND}__new_pre
  item_hook "$_VAULT_KIND" new_pre \
    || {
      _log ERROR "Failed hook: new_pre for $_VAULT_KIND"
      return 1 
    }
    
  # Check recipients
  [[ -n "$idents" ]] || {
    _log ERROR "Missing recipient(s)"
    return 1
  }

  # Save in DB
  if [[ "$idents" == 'ALL' ]]; then
    _dir_db set "$_VAULT_KIND.$_VAULT_NAME.shared" "true"
    valid=true
    idents=$(lib_id_list | join_lines )
  else
    # Validate idents
    for ident in $idents; do
      [[ -n "$ident" ]] || continue
      lib_id_exists "$ident" || {
        _log ERROR "Ident '$ident' does not exists"
        return 1
      }
    done
    # Save idents
    for ident in $idents; do
      [[ -n "$ident" ]] || continue
      _dir_db add "$_VAULT_KIND.$_VAULT_NAME.recipient" "$ident"
      valid=true
    done
  fi

  if ! $valid; then
    _log ERROR 'Missing valid idents, abort !'
    return 1
  fi

  # Create hash
  _log INFO "Create new $_VAULT_KIND '$_VAULT_NAME' for: $idents"
  _dir_db set "$_VAULT_KIND.$_VAULT_NAME.store-hash" "$_VAULT_HASH"

  # HOOK: ${_VAULT_KIND}__new_post
  item_hook "$_VAULT_KIND" new_post \
    || {
      _log ERROR "Failed hook: new_post for $_VAULT_KIND"
      return 1 
    }

}


# Remove an item from config
item_rm() {
  item_load_existing "$1" || return $?; shift 1
  local changed=false

  # HOOK: ${_VAULT_KIND}__rm_pre
  item_hook "$_VAULT_KIND" rm_pre \
    || {
      _log ERROR "Failed hook: rm_pre for $_VAULT_KIND"
      return 1 
    }

  # Sanity checks
  [[ -n "$_VAULT_HASH" ]] || {
    _log ERROR "Could not get $_VAULT_KIND store hash"
    return 1
  }

  # Clear encrypted file
  if [[ -f "$_VAULT_ENC" ]]; then
    _log INFO "Delete encrypted $_VAULT_KIND file: $_VAULT_ENC"
    rm "$_VAULT_ENC"
    changed=true
  fi

  # Clear opened dir
  if [[ -d "$_VAULT_DIR" ]]; then
    local erase=false

    if $APP_FORCE; then
      erase=true
    else
      erase=false
      _confirm \
        "Do you want to delete directory '$_VAULT_DIR' data ?" &&
        erase=true
    fi

    if $erase; then
      _log INFO "Delete local secret data in '$_VAULT_DIR'"
      _exec rm -rf "$_VAULT_DIR"
      changed=true
    else
      _log WARN "Local secret data in '$_VAULT_DIR' wont be deleted!"
    fi
  fi

  # HOOK: ${_VAULT_KIND}_rm_post


  # Clear configuration
  if item_assert_exists2 "$_VAULT_NAME"; then
    _dir_db rms "$_VAULT_KIND.$_VAULT_NAME"
    changed=true
  fi

  # HOOK: ${_VAULT_KIND}__rm_post
  item_hook "$_VAULT_KIND" rm_post \
    || {
      _log ERROR "Failed hook: rm_post for $_VAULT_KIND"
      return 1 
    }


  # report to user
  if $changed; then
    _log INFO "$_VAULT_KIND '$_VAULT_NAME' has been removed"
  else
    _log INFO "$_VAULT_KIND '$_VAULT_NAME' does not exists"
  fi

}



# Push secrets into encrypted file
item_push() {
  item_load_existing "$1" || return $?; shift 1

  # Load hooks: push_init
  item_hook "$_VAULT_KIND" push_init \
    || {
      _log ERROR "Failed hook: push_init for $_VAULT_KIND"
      return 1 
    }

  
  # Sanity checks
  [[ -d "$_VAULT_DIR" ]] || {
    _log DEBUG "Vault '$_VAULT_NAME' already closed/locked"
    return 0
  }
  [[ -n "$_VAULT_HASH" ]] || {
    _log ERROR "Could not get vault '$_VAULT_NAME' store-hash"
    return 1
  }

  # Load hooks: push_pre
  item_hook "$_VAULT_KIND" push_pre \
    || {
      _log ERROR "Failed hook: push_pre for $_VAULT_KIND"
      return 1 
    }


  # Ensure you have opened the last version
  local prev_file_ts=$(_cache_db get "vault.$_VAULT_NAME.ts-open" 2>/dev/null || echo '0')
  local file_ts=$(stat -c %Y "$_VAULT_ENC" 2>/dev/null || echo 0)

  if [[ "$prev_file_ts" -gt 0 ]] && [[ "$file_ts" -gt 0 ]] ; then
    # Compare file time stamps
    if [[ "${file_ts}" -gt "$prev_file_ts" ]]; then
      echo "$file_ts VS $prev_file_ts"
      _log ERROR "Vault changed since opened, please do pull first for $_VAULT_NAME!"
      return 1
    fi
  fi

  # Build recipient list
  local idents=
  idents=$(item_recipient_idents2 "$_VAULT_NAME")
  [[ -n "$idents" ]] || {
    _log ERROR "Could not find any idents attached to vault '$_VAULT_NAME'"
    return 1
  }
  ident_names=$(join_lines <<<"$idents")
  _log INFO "Sharing vault '$_VAULT_NAME' with idents: ${ident_names}"

  # Validate recipient list
  local age_recipient_args=
  age_recipient_args=$(item_recipient_idents_age_args "$idents")
  [[ -n "$age_recipient_args" ]] || {
    _log ERROR "No vault identity matched for: $_VAULT_NAME"
    return 1
  }

  # Ensure checksum does not match
  local changed="with changes"
  # tree -a "$_VAULT_DIR"
  local content_checksum=$( { echo "$idents"; tar -czf - -C "$_VAULT_DIR" . ; } | hash_sum -)
  # local content_checksum=$(tree -a "$_VAULT_DIR"  | hash_sum -)
  local old_checksum=$(_cache_db get "vault.$_VAULT_NAME.checksum" 2>/dev/null || true)


  if [[ -n "$old_checksum" ]] && [[ "$old_checksum" == "$content_checksum" ]]; then
    changed="without changes"
    if $APP_FORCE; then
      _log INFO "Forcing push even if not necessary because of --force"
    else
      _log INFO "No changes in '$_VAULT_NAME', not reencrypting, use --force"
      return 0
    fi
  else
    _log INFO "Changes detected in '$_VAULT_NAME', rencrypting data"
  fi


  # Encrypt data
  _log INFO "Update vault '$_VAULT_NAME' file: $_VAULT_ENC"

  if ! $APP_DRY; then
    _cache_db set "vault.$_VAULT_NAME.checksum" "$content_checksum"
    ensure_dir "$APP_STORES_DIR"
    # shellcheck disable=SC2086
    tar -czf - -C "$_VAULT_DIR" . \
      | age --encrypt --armor -output "$_VAULT_ENC" $age_recipient_args \
      || _die 1 "Failed to encrypt vault"

    _cache_db set "vault.$_VAULT_NAME.ts-open" "$(stat -c "%Y" "$_VAULT_ENC")"
  else
    _log DRY "Update encrypted file: $_VAULT_ENC"
  fi


  # Load hooks: push_post
  item_hook "$_VAULT_KIND" push_post \
    || {
      _log ERROR "Failed hook: push_post for $_VAULT_KIND"
      return 1 
    }

  _log INFO "Vault '$_VAULT_NAME' pushed successfully $changed."
}


# Fech secret from encrypted data
item_pull (){
  
  item_load_existing "$1" || return $?; shift 1

  local ident=${@}

  # Load hooks: pull_init
  item_hook "$_VAULT_KIND" pull_init \
    || {
      _log ERROR "Failed hook: pull_init for $_VAULT_KIND"
      return 1 
    }

  # Sanity check
  [[ -f "$_VAULT_ENC" ]] || {
    _log INFO "Encrypted file for vault '$_VAULT_NAME' does not exists: $_VAULT_ENC"
    return 1
  }
  [[ -n "$_VAULT_HASH" ]] || {
    _log ERROR "Could not get vault store-hash"
    return 1
  }

  # Ensure you have opened the last version
  local prev_file_ts=$(_cache_db get "vault.$_VAULT_NAME.ts-open" 2>/dev/null || echo '0')
  local file_ts=$(stat -c %Y "$_VAULT_ENC" 2>/dev/null || echo 0)

  if [[ "$prev_file_ts" -gt 0 ]] && [[ "$file_ts" -gt 0 ]] ; then
    # Compare file time stamps
    if [[ "${file_ts}" -eq "$prev_file_ts" ]]; then
      if $APP_FORCE; then
        _log INFO "Already up to date, but continue because of --force"
      else
        _log INFO "Already up to date, use '--force' to force"
        return 0
      fi
    elif [[ "${file_ts}" -gt "$prev_file_ts" ]]; then
      _log INFO "Upstream file has been updated, need to update"
    else
      _log WARN "Something went wrong with timestamps: ${file_ts} -lt $prev_file_ts"
    fi
  fi
  _cache_db set "vault.$_VAULT_NAME.ts-open" "$file_ts"

  # Fetch default recipients
  if [[ -z "$ident" ]]; then
    ident=$(item_recipient_idents2 "$_VAULT_NAME")
    local count=$(wc -l <<<"$ident")
    if [[ "$count" -eq 0 ]]; then
      _log ERROR "Failed to fetch vault associated ids: $_VAULT_NAME"
      return 1
    elif [[ "$count" -gt 1 ]]; then
      # TODO: Allow ot manage current ID
      ident_names=$(xargs <<<"$ident")
      _log ERROR "Too many ids for vault '$_VAULT_NAME', choose one of: ${ident_names// /,}"
      return 1 
    fi
  fi

  # Load ident
  _log INFO "Decrypting with ident '$ident'"
  cb_init_ident "$ident"
  cb_init_ident_pass

  # HOOK: ${_VAULT_KIND}__pull_pre
  item_hook "$_VAULT_KIND" pull_pre \
    || {
      _log ERROR "Failed hook: pull_pre for $_VAULT_KIND"
      return 1 
    }

  _log DEBUG "Opening '$_VAULT_ENC' with ident '$ident' in: $_VAULT_DIR"

  # Decrypt file
  ensure_dir "$_VAULT_DIR"
  if ! $APP_DRY; then
    _age_decrypt_with_ident \
      --output - "$_VAULT_ENC" | tar -xz -C "$_VAULT_DIR" || \
      {
        _exec rmdir "$_VAULT_DIR" 2>/dev/null || true
        _log ERROR "Failed to decrypt file: $_VAULT_ENC"
        _log HINT "Fail reasons:"
        _log HINT "* Check if $ident password is correct"
        # _log HINT "* Retry with --no-keyring option"
        return 1
      }
  fi

  # HOOK: ${_VAULT_KIND}_pull_post
  item_hook "$_VAULT_KIND" pull_post \
    || {
      _log ERROR "Failed hook: pull_post for $_VAULT_KIND"
      return 1 
    }

  _log INFO "Vault '$_VAULT_NAME' pulled successfully in $_VAULT_DIR"

}



# Fech secret from encrypted data
item_lock (){
  item_load "$1" "$2"; shift 2

  item_push "$_VAULT_NAME"
  item_hook "$_VAULT_KIND" lock_post \
    || {
      _log ERROR "Failed hook: lock_post for $_VAULT_KIND"
      return 1 
    }

}


item_unlock (){
  item_load "$1" "$2"; shift 2

  item_pull "$_VAULT_NAME" "$ident"
  item_hook "$_VAULT_KIND" unlock_post \
    || {
      _log ERROR "Failed hook: unlock_post for $_VAULT_KIND"
      return 1 
    }
}
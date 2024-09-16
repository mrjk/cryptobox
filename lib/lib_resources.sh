
# Item management (internal)
# =================

# Start a hook
item_hook() {
  
  local kind=$1
  local cmd=$2
  shift 2 || true

  [ -n "$cmd" ] || _die 3 "Missing kind name, this is a bug"
  local fn_name="lib_${kind}_hook__${cmd}"
  if [[ $(type -t "${fn_name}") == function ]]; then
    _log INFO "Executing hook: $fn_name for ${vault_name:-}"
    "${fn_name}" "$@"
    return $?
  fi
}


## Multi kind functions
#  ------
APP_ITEMS_KINDS=""


# List opened vaults
item_opened_secrets() {
  local kinds=${1:-$APP_ITEMS_KINDS}
  local ident=${2:-}


  for kind in $kinds; do

    if [[ -n "$ident" ]]; then
      local vaults=$(item_ident_resources "$ident"  "$kind")
    else
      local vaults=$(item_list_names "$kind")
    fi

    for name in $vaults; do
      [[ -d "$APP_VAULTS_DIR/$name" ]] && echo "$name"
    done
  done
}

# Sync all items
items_push_opened (){
  local ident=$1
  local kinds=$APP_ITEMS_KINDS
  # Check all opened vaults
  for kind in $kinds; do
    for vault in $(item_opened_secrets "$kind" "$ident"); do
      _log DEBUG "Pushing vault: $vault"
      item_push "$kind" "$vault"
    done
  done
}

# Pull all items
items_pull_opened (){
  local ident=$1
  local kinds=$APP_ITEMS_KINDS
  # Check all opened vaults
  for kind in $kinds; do
    for vault in $(item_opened_secrets "$kind" "$ident"); do
      _log DEBUG "Pulling vault: $vault"
      item_pull "$kind" "$vault" "$ident"
    done
  done
}

## Per kind functions
#  ------

# Return item's kind
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

  for kind in $kinds; do
    
    _dir_db dump "$kind." |
      grep "=$ident$" |
      sed 's/^'"$kind"'.//;s/\..*//' |
      sort -u
  done
}

# Get item name from hash
item_name_from_hash() {
  local needle=$1
  local kinds=${2:-$APP_ITEMS_KINDS}

  for kind in $kinds; do
    
    _dir_db dump "$kind." |
      grep "store-hash=$needle$" |
      sed 's/^'"$kind"'.//;s/\..*//' |
      sort -u
  done
}

# List all resources of kind
item_list_names() {
  local kind=$1
  _dir_db dump "$kind." |
    sed 's/^'"$kind"'.//;s/\..*//' |
    sort -u
}

# Check if a given kind resource exist
item_assert_exists() {
  local kind=$1
  local name=$2

  item_list_names "$kind" | grep -q "^$name$"
  return $?
}


# Return all recipients ids for a given vault
item_recipient_idents() {
  local kind=$1
  local vault_name=$2
  _dir_db get "$kind.$vault_name.recipient" |
    sort -u
}

# Return age pub_keys from recipients
item_recipient_idents_age_args() {
  local kind=$1
  local vault_name=$2
  local idents=
  idents=$(item_recipient_idents "$kind" "$vault_name")

  local ret=
  for ident in $idents; do
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



# Create a new item in config
# Asssert item does not already exists
# Check recipients
# Create store-hash
# Add recipients to config
# Continue if not fails
# Kind: vault, gitvault ...
item_new() {
  local kind=$1
  local vault_name=$2
  shift 2
  local idents=${@:-}

  local valid=false

  # Sanity check
  item_assert_exists "$kind" "$vault_name" && {
    _log INFO "Vault '$vault_name' already exists."
    return 0
  }
    
  # Check recipients
  [[ -n "$idents" ]] || {
    _log ERROR "Missing recipient(s)"
    return 1
  }
  # set -x
  for ident in $idents; do
    [[ -n "$ident" ]] || continue
    lib_id_exists "$ident" || {
      _log ERROR "Ident '$ident' does not exists"
      return 1
    }
  done

  # Save in DB
  for ident in $idents; do
    [[ -n "$ident" ]] || continue
    _dir_db add "$kind.$vault_name.recipient" "$ident"
    valid=true
  done

  if ! $valid; then
    _log ERROR 'Missing valid idents, abort !'
    return 1
  fi

  # Create hash
  _log INFO "Create new $kind '$vault_name' for: $idents"
  local vault_hash=$(hash_sum "$vault_name")
  _dir_db set "$kind.$vault_name.store-hash" "$vault_hash"

  # set -x
  # HOOK: ${kind}_new_final
  item_hook "$kind" new_final \
    || {
      _log ERROR "Failed hook: new_final for $kind"
      return 1 
    }


}


# Remove an item from config
item_rm() {
  local kind=$1
  local vault_name=$2
  local changed=false

  # Build vars
  local vault_hash=$(_dir_db get "$kind.$vault_name.store-hash")
  local vault_enc="$APP_STORES_DIR/$vault_hash.age"
  local vault_dir="$APP_VAULTS_DIR/$vault_name"

  # Sanity checks
  [[ -n "$vault_hash" ]] || {
    _log ERROR "Could not get $kind store hash"
    return 1
  }

  # HOOK: ${kind}_rm_pre

  # Clear encrypted file
  if [[ -f "$vault_enc" ]]; then
    _log INFO "Delete encrypted $kind file: $vault_enc"
    rm "$vault_enc"
    changed=true
  fi

  # Clear opened dir
  if [[ -d "$vault_dir" ]]; then
    local erase=false

    if $APP_FORCE; then
      erase=true
    else
      erase=false
      _confirm \
        "Do you want to delete directory '$vault_dir' data ?" &&
        erase=true
    fi

    if $erase; then
      _log INFO "Delete local secret data in '$vault_dir'"
      _exec rm -rf "$vault_dir"
      changed=true
    else
      _log WARN "Local secret data in '$vault_dir' wont be deleted!"
    fi
  fi

  # HOOK: ${kind}_rm_post


  # Clear configuration
  if item_assert_exists "$kind" "$vault_name"; then
    _dir_db rms "$kind.$vault_name"
    changed=true
  fi

  # HOOK: ${kind}_rm_final
  item_hook "$kind" rm_final \
    || {
      _log ERROR "Failed hook: rm_final for $kind"
      return 1 
    }


  # report to user
  if $changed; then
    _log INFO "$kind '$vault_name' has been removed"
  else
    _log INFO "$kind '$vault_name' does not exists"
  fi

}



# Push secrets into encrypted file
item_push() {
  local kind=$1
  local vault_name=$2
  vault_dir="$APP_VAULTS_DIR/$vault_name"

  # local vault_dir=${3:-}

  # HOOK: ${kind}__push_pre
  item_hook "$kind" push_pre \
    || {
      _log ERROR "Failed hook: push_pre for $kind"
      return 1 
    }

  # # Guess vault_dir
  # if [[ -z "$vault_dir" ]]; then
  # case "$kind" in
  #   vault) 
  #     vault_dir="$APP_VAULTS_DIR/$vault_name"
  #     ;;
  #   gitvault) 
  #     vault_dir="$APP_SPOOL_DIR/$vault_name"
  #     ;;
  # esac
  # fi

  # Build vars
  local vault_hash=$(_dir_db get "$kind.$vault_name.store-hash")
  local vault_enc="$APP_STORES_DIR/$vault_hash.age"
  # local vault_dir="$APP_VAULTS_DIR/$vault_name"

  # Sanity checks
  item_assert_exists "$kind" "$vault_name" || {
    _log ERROR "Unknown $kind: '$vault_name', available names are: $(item_list_names "$kind" | tr '\n' ',')"
    return 1
  }
    
  [[ -d "$vault_dir" ]] || {
    _log DEBUG "$kind '$vault_name' already closed/locked"
    return 0
  }
  [[ -n "$vault_hash" ]] || {
    log ERROR "Could not get $kind store-hash"
    return 1
  }

  # HOOK: ${kind}_push_post
  item_hook "$kind" push_post \
    || {
      _log ERROR "Failed hook: push_post for $kind"
      return 1 
    }

  # Gitvault specificties
  # if [[ "$kind" == "gitvault" ]]; then
  #   local target_dir="$APP_VAULTS_DIR/$vault_name"
  #   if [[ -d "$target_dir" ]]; then
  #     _log DEBUG "Push local change to gitvault"
  #     _exec git -C "$target_dir" push 2>/dev/null
  #   else
  #     _log DEBUG "Skip git push because vault not mounted"
  #   fi
  # fi

  # Fetch recipients
  age_recipient_args=$(item_recipient_idents_age_args "$kind" "$vault_name")
  [[ -n "$age_recipient_args" ]] || {
    _log ERROR "No $kind identity matched for: $vault_name"
    return 1
  }

  # Encrypt
  local content_checksum=$(tar -czf - -C "$vault_dir" . | hash_sum -)
  local old_checksum=$(_cache_db get "$kind.$vault_name.checksum")

  local ret=0
  local changed="without changes"
  if [[ "$old_checksum" == "$content_checksum" ]]; then
    _log DEBUG "No changes in $kind, not reencrypting"
  else
    changed="with changes"
    _log DEBUG "Changes detected in $kind, rencrypting data"
    if ! $APP_DRY; then
      _cache_db set "$kind.$vault_name.checksum" "$content_checksum"
      ensure_dir "$APP_STORES_DIR"
      # shellcheck disable=SC2086
      tar -czf - -C "$vault_dir" . | age --encrypt --armor -output "$vault_enc" $age_recipient_args
      ret=$?
    else
      _log DRY "Update encrypted file: $vault_enc"
    fi
  fi

  # HOOK: ${kind}_push_final
  item_hook "$kind" push_final \
    || {
      _log ERROR "Failed hook: push_final for $kind"
      return 1 
    }


  _log INFO "$kind '$vault_name' pushed successfully $changed."

}

# Fech secret from encrypted data
item_pull (){
  local kind=$1
  local vault_name=$2
  local ident=${3:-}
  local vault_dir="$APP_VAULTS_DIR/$vault_name"


  # HOOK: ${kind}_pull_pre
  item_hook "$kind" pull_pre \
    || {
      _log ERROR "Failed hook: pull_pre for $kind"
      return 1 
    }


  # Guess vault_dir
  # case "$kind" in
  #   vault) 
  #     vault_dir="$APP_VAULTS_DIR/$vault_name"
  #     ;;
  #   gitvault) 
  #     vault_dir="$APP_SPOOL_DIR/$vault_name"
  #     ;;
  # esac

  # Build vars
  local vault_hash=$(_dir_db get "$kind.$vault_name.store-hash")
  local vault_enc="$APP_STORES_DIR/$vault_hash.age"
  # local vault_dir="$APP_VAULTS_DIR/$vault_name"

  # HOOK: ${kind}_pull_pre

  # Sanity check
  if ! item_assert_exists "$kind" "$vault_name"; then
    _log ERROR "Unknown $kind: '$vault_name', available names are: $(item_list_names "$kind" | tr '\n' ',')"
    return 1
  fi
  # TMP: [[ ! -d "$vault_dir" ]] || _die 0 "Already opened in $vault_dir"
  [[ -f "$vault_enc" ]] || {
    _log INFO "Encrypted file for $kind '$vault_name' does not exists: $vault_enc"
    return 1
  }
  [[ -n "$vault_hash" ]] || {
    _log ERROR "Could not get $kind store-hash"
    return 1
  }

  # Fetch default recipients
  if [[ -z "$ident" ]]; then
    ident=$(item_recipient_idents "$kind" "$vault_name")
    local count=$(wc -l <<<"$ident")
    if [[ "$count" -eq 0 ]]; then
      _log ERROR "Failed to fetch $kind associated ids: $vault_name"
      return 1
    elif [[ "$count" -gt 1 ]]; then
      # TODO: Allow ot manage current ID
      ident_names=$(xargs <<<"$ident")
      _log ERROR "Too many ids for $kind '$vault_name', choose one of: ${ident_names// /,}"
      return 1 
    fi
  fi

  # echo "PASS IDENT LOADING"
  # echo "vault_hash=$vault_hash"
  # echo "vault_enc=$vault_enc"
  # echo "vault_dir=$vault_dir"
  # echo "ident=$ident"
  # echo ""

  # Load ident
  cb_init_ident "$ident"

  _log DEBUG "Opening '$vault_enc' with ident '$ident' in: $vault_dir"
  
  # HOOK: ${kind}_pull_post
  item_hook "$kind" pull_post \
    || {
      _log ERROR "Failed hook: pull_post for $kind"
      return 1 
    }


  # HOOK: ${kind}_pull_post
  # if [[ "$kind" == "vault" ]]; then
  #   # Delete existing content, so deleted files are not re-propagated
  #   if $APP_FORCE; then
  #     _log WARN "Local changes in '$vault_dir' will be lost after update"
  #     rm -rf "$vault_dir"
  #   else
  #     _log DEBUG "Local changes in '$vault_dir' are kept, deleted files may reappear. Use '-f' to delete first."
  #   fi
  # fi




  ensure_dir "$vault_dir"
  if ! $APP_DRY; then
    _age_decrypt_with_ident \
      --output - "$vault_enc" | tar -xz -C "$vault_dir"
    local rc=$?

    if [[ "$rc" -ne 0 ]]; then
      _exec rmdir "$vault_dir"
      _log ERROR "Failed to decrypt file: $vault_enc"
      return 1
    fi
  fi

  # Do gitvault specificties
  # if [[ "$kind" == "gitvault" ]]; then
  #   local target_dir="$APP_VAULTS_DIR/$vault_name"

  #   if [[ -d "$target_dir" ]]; then
  #     _log DEBUG "Pull from local remote"
  #     _exec git -C "$target_dir" pull --rebase >/dev/null
  #   else
  #     _log DEBUG "Clone from local remote"
  #     ensure_dir "$target_dir"
  #     _exec git clone "$APP_SPOOL_DIR/$vault_name" "$target_dir" >/dev/null
  #   fi
  # fi

  # HOOK: ${kind}_pull_final
  item_hook "$kind" pull_final \
    || {
      _log ERROR "Failed hook: pull_final for $kind"
      return 1 
    }

  _log INFO "Vault '$vault_name' pulled successfully in $vault_dir"

}

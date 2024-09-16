
# Item management (internal)
# =================



## Multi kind functions
#  ------
APP_ITEMS_KINDS="vault gitvault"


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
  item_assert_exists "$kind" "$vault_name" &&
    _die 0 "Vault '$vault_name' already exists."
  
  # Check recipients
  [[ -n "$idents" ]] || _die 1 "Missing recipient(s)"
  for ident in $idents; do
    [[ -n "$ident" ]] || continue
    lib_id_exists "$ident" ||
      _die 1 "Ident '$ident' does not exists"
  done

  # Save in DB
  for ident in $idents; do
    [[ -n "$ident" ]] || continue
    _dir_db add "$kind.$vault_name.recipient" "$ident"
    valid=true
  done

  if ! $valid; then
    _die 1 'Missing valid idents, abort !'
  fi

  # Create hash
  _log INFO "Create new $kind '$vault_name' for: $idents"
  local vault_hash=$(hash_sum "$vault_name")
  _dir_db set "$kind.$vault_name.store-hash" "$vault_hash"

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
  [[ -n "$vault_hash" ]] || _die 1 "Could not get $kind store hash"

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

  # Clear configuration
  if item_assert_exists "$kind" "$vault_name"; then
    _dir_db rms "$kind.$vault_name"
    changed=true
  fi

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
  # local vault_dir=${3:-}

  # Guess vault_dir
  # if [[ -z "$vault_dir" ]]; then
  case "$kind" in
    vault) 
      vault_dir="$APP_VAULTS_DIR/$vault_name"
      ;;
    gitvault) 
      vault_dir="$APP_SPOOL_DIR/$vault_name"
      ;;
  esac
  # fi

  # Build vars
  local vault_hash=$(_dir_db get "$kind.$vault_name.store-hash")
  local vault_enc="$APP_STORES_DIR/$vault_hash.age"
  # local vault_dir="$APP_VAULTS_DIR/$vault_name"

  # Sanity checks
  item_assert_exists "$kind" "$vault_name" ||
    _die 1 "Unknown $kind: '$vault_name', available names are: $(item_list_names "$kind" | tr '\n' ',')"
  [[ -d "$vault_dir" ]] || {
    _log DEBUG "$kind '$vault_name' already closed/locked"
    return 0
  }
  [[ -n "$vault_hash" ]] || _die 1 "Could not get $kind store-hash"

  # Gitvault specificties
  if [[ "$kind" == "gitvault" ]]; then
    local target_dir="$APP_VAULTS_DIR/$vault_name"
    if [[ -d "$target_dir" ]]; then
      _log DEBUG "Push local change to gitvault"
      _exec git -C "$target_dir" push 2>/dev/null
    else
      _log DEBUG "Skip git push because vault not mounted"
    fi
  fi

  # Fetch recipients
  age_recipient_args=$(item_recipient_idents_age_args "$kind" "$vault_name")
  [[ -n "$age_recipient_args" ]] || _die 1 "No $kind identity matched for: $vault_name"

  # Encrypt
  local content_checksum=$(tar -czf - -C "$vault_dir" . | hash_sum -)
  local old_checksum=$(_dir_db get "$kind.$vault_name.checksum")

  local ret=0
  local changed="without changes"
  if [[ "$old_checksum" == "$content_checksum" ]]; then
    _log DEBUG "No changes in $kind, not reencrypting"
  else
    changed="with changes"
    _log DEBUG "Changes detected in $kind, rencrypting data"
    if ! $APP_DRY; then
      _dir_db set "$kind.$vault_name.checksum" "$content_checksum"
      ensure_dir "$APP_STORES_DIR"
      # shellcheck disable=SC2086
      tar -czf - -C "$vault_dir" . | age --encrypt --armor -output "$vault_enc" $age_recipient_args
      ret=$?
    else
      _log DRY "Update encrypted file: $vault_enc"
    fi
  fi

  _log INFO "$kind '$vault_name' pushed successfully $changed."

}

# Fech secret from encrypted data
item_pull (){
  local kind=$1
  local vault_name=$2
  local ident=${3:-}
  local vault_dir='' #$3

  # Guess vault_dir
  case "$kind" in
    vault) 
      vault_dir="$APP_VAULTS_DIR/$vault_name"
      ;;
    gitvault) 
      vault_dir="$APP_SPOOL_DIR/$vault_name"
      ;;
  esac

  # Build vars
  local vault_hash=$(_dir_db get "$kind.$vault_name.store-hash")
  local vault_enc="$APP_STORES_DIR/$vault_hash.age"
  # local vault_dir="$APP_VAULTS_DIR/$vault_name"

  # Sanity check
  item_assert_exists "$kind" "$vault_name" ||
    _die 1 "Unknown $kind: '$vault_name', available names are: $(item_list_names "$kind" | tr '\n' ',')"
  # TMP: [[ ! -d "$vault_dir" ]] || _die 0 "Already opened in $vault_dir"
  [[ -n "$vault_hash" ]] || _die 1 "Could not get $kind store-hash"

  # Fetch default recipients
  if [[ -z "$ident" ]]; then
    ident=$(item_recipient_idents "$kind" "$vault_name")
    local count=$(wc -l <<<"$ident")
    if [[ "$count" -eq 0 ]]; then
      _die 1 "Failed to fetch $kind associated ids: $vault_name"
    elif [[ "$count" -gt 1 ]]; then
      # TODO: Allow ot manage current ID
      ident_names=$(xargs <<<"$ident")
      _die 1 "Too many ids for $kind '$vault_name', choose one of: ${ident_names// /,}"
    fi
  fi

  # echo "PASS IDENT LOADING"
  # echo "vault_hash=$vault_hash"
  # echo "vault_enc=$vault_enc"
  # echo "vault_dir=$vault_dir"
  # echo "ident=$ident"
  # echo ""

  # Load ident
  load_ident "$ident"

  _log DEBUG "Opening '$vault_enc' with ident '$ident' in: $vault_dir"
  
  if [[ "$kind" == "vault" ]]; then
    # Delete existing content, so deleted files are not re-propagated
    if $APP_FORCE; then
      _log WARN "Local changes in '$vault_dir' will be lost after update"
      rm -rf "$vault_dir"
    else
      _log DEBUG "Local changes in '$vault_dir' are kept, deleted files may reappear. Use '-f' to delete first."
    fi
  fi

  ensure_dir "$vault_dir"
  if ! $APP_DRY; then
    _age_decrypt_with_ident \
      --output - "$vault_enc" | tar -xz -C "$vault_dir"
    local rc=$?

    if [[ "$rc" -ne 0 ]]; then
      _exec rmdir "$vault_dir"
      _die 1 "Failed to decrypt file: $vault_enc"
    fi
  fi

  # Do gitvault specificties
  if [[ "$kind" == "gitvault" ]]; then
    local target_dir="$APP_VAULTS_DIR/$vault_name"

    if [[ -d "$target_dir" ]]; then
      _log DEBUG "Pull from local remote"
      _exec git -C "$target_dir" pull --rebase >/dev/null
    else
      _log DEBUG "Clone from local remote"
      ensure_dir "$target_dir"
      _exec git clone "$APP_SPOOL_DIR/$vault_name" "$target_dir" >/dev/null
    fi
  fi

  _log INFO "Vault '$vault_name' pulled successfully in $vault_dir"

}

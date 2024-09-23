


# DB Commands
# =================

# VALIDATED
_db() {
  local config=$1
  shift 1
  _log TRACE "Query db: git-db -s '$config' $@"
  git-db -s "$config" "$@" 2>/dev/null
}

# Ensure workspace is unlocked
_db_ensure_open() {
  if [[ ! -f "$APP_CONFIG_FILE" ]]; then

    if [[ ! -f "$APP_CONFIG_FILE_ENC" ]]; then
      _log INFO "Config does not exists: $APP_CONFIG_FILE"

      return 1
      _log INFO "Create a new config file: $APP_CONFIG_FILE"
      _exec git-db init "$APP_CONFIG_FILE" #2>/dev/null
    else
      _die 1 "You must unlock repo first!"
    fi
  fi
}

# Ensure workspace is unlocked
_db_ensure_created() {
  local file=${1:-$APP_CONFIG_FILE}

  if [[ -f "$file" ]]; then
    _log TRACE "Config file already exists : $file"
    return
  fi

  # if [[ -f "${APP_CONFIG_FILE_ENC:-NONE}" ]]; then
  #   _log TRACE "Config file already exists and it's encrypted: $APP_CONFIG_FILE_ENC"
  #   return
  # fi

  _log INFO "Create a new config file: $file"
  _exec git-db init "$file" 2>/dev/null
  
}
_db_is_open () {
  local file=${1:-$APP_CONFIG_FILE}
  [[ -f "$file" ]] || return 1
}

_cache_db() {
  local target=$APP_CACHE_FILE

  # TO BE REMOVED LATER
  # Ensure config is present

    if [[ ! -f "$target" ]]; then
        _log INFO "Create a new cache file: $target"
        _exec git-db init "$target" 2>/dev/null \
            || _die 1 "Can't create cache file!" 
    fi


  # Call db backend
  local xtra_args=
  ${APP_DRY} && xtra_args='-n'
  _db "$target" $xtra_args "$@"

}

# VALIDATED
# Directory DB
_dir_db() {

  # TO BE REMOVED LATER
  # Ensure config is present
  if [[ ! -f "$APP_CONFIG_FILE" ]]; then

    if [[ ! -f "$APP_CONFIG_FILE_ENC" ]]; then
      _log INFO "No config exists: $APP_CONFIG_FILE"

      return 0
      # _log INFO "Create a new config file: $APP_CONFIG_FILE"
      # _exec git-db init "$APP_CONFIG_FILE" #2>/dev/null
    else
      _die 1 "You must unlock repo first!"
    fi

  fi

  # Call db backend
  local xtra_args=
  ${APP_DRY} && xtra_args='-n'
  _db "$APP_CONFIG_FILE" $xtra_args "$@"

}


# Transform db dump into vars.
# TOFIX: How it works with multilines ?
_db_to_vars() {
  sed -E "s/\./__/;s/\./__/;s/=/='/;s/$/'/;s/^/db__/"
}


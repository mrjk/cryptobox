


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
      _log INFO "Create a new config file: $APP_CONFIG_FILE"
      _exec git-db init "$APP_CONFIG_FILE" #2>/dev/null
    else
      _die 1 "You must unlock repo first!"
    fi
  fi
}

# VALIDATED
# Directory DB
_dir_db() {

  # TO BE REMOVED LATER
  # Ensure config is present
  if [[ ! -f "$APP_CONFIG_FILE" ]]; then

    if [[ ! -f "$APP_CONFIG_FILE_ENC" ]]; then
      _log INFO "Create a new config file: $APP_CONFIG_FILE"
      _exec git-db init "$APP_CONFIG_FILE" #2>/dev/null
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





# GitVault management (public)
# =================

# Create a new gitvault
lib_gitvault_new () {
  local vault_name=$1
  shift 1
  local idents=${@:-}

  # Create new item
  item_new gitvault "$vault_name" "$idents"

  # Create git spool
  local repo_spool="$APP_SPOOL_DIR/$vault_name"
  git init --bare "$repo_spool"

  # Create vault
  local vault_dest="$APP_VAULTS_DIR/$vault_name"
  git clone "$repo_spool" "$vault_dest" 2>/dev/null

  _log INFO "New gitvault created in: $vault_dest"
}


# Remove and delete vault
lib_gitvault_rm() {
  local vault_name=$1
  item_rm gitvault "$vault_name"

  # Clean spool
  local repo_spool="$APP_SPOOL_DIR/$vault_name"

  [[ ! -e "$repo_spool" ]] || _exec rm -rf "$repo_spool"

}


# Push changes and clean
lib_gitvault_lock() {
  local vault_name=$1

  local ret=''
  item_push gitvault "$vault_name"
  ret=$?

  # Validate
  [[ "$ret" -eq "0" ]] ||
    _die "$ret" "Some errors happened, did not remove local data!"

  # Cleanup
  _exec rm -rf "$APP_SPOOL_DIR/$vault_name"
  _exec rm -rf "$APP_VAULTS_DIR/$vault_name"
  _log INFO "gitvault '$vault_name' closed successfully."

}

# Decrypt and open vault
lib_gitvault_unlock() {
  local vault_name=$1
  shift 1
  local ident=${@:-}

  item_pull gitvault "$vault_name" "$ident"

  ensure_dir "$APP_VAULTS_DIR/$vault_name"
  (
    cd "$APP_VAULTS_DIR/$vault_name"
    git clone "$APP_SPOOL_DIR/$vault_name" .
  )
  
  _log INFO "gitvault '$vault_name' opened successfully."

}


# Push changes and clean
lib_gitvault_push() {
  local vault_name=$1

  # local target_dir="$APP_VAULTS_DIR/$vault_name"
  # if [[ -d "$target_dir" ]]; then
  #   (
  #     cd "$target_dir"
  #     git push
  #   )
  # else
  #   _log DEBUG "Skip git pull because vault not mounted"
  # fi

  # local ret=''
  item_push gitvault "$vault_name"
  # ret=$?

  # # Validate
  # [[ "$ret" -eq "0" ]] ||
  #   _die "$ret" "Some errors happened, did not remove local data!"

}

# Decrypt and open vault
lib_gitvault_pull() {
  item_pull gitvault "$@"

  # local vault_name=$1
  # shift 1
  # local ident=${@:-}


  # local target_dir="$APP_VAULTS_DIR/$vault_name"

  # if [[ -d "$target_dir" ]]; then
  #   (
  #     cd "$target_dir"
  #     git pull
  #   )
  # else
  #   ensure_dir "$target_dir"
  #   (
  #     cd "$target_dir"
  #     git clone "$APP_SPOOL_DIR/$vault_name" .
  #   )
  # fi
  
  # _log INFO "gitvault '$vault_name' opened successfully."

}








# CLI gitvault Commands
# =================

# Display help message
cli__gitvault_usage() {
  cat <<EOF
${APP_NAME}: Manage gitvaults (Subcommand example)

usage: ${APP_NAME} gitvault [OPTS] add NAME
       ${APP_NAME} gitvault [OPTS] rm NAME
       ${APP_NAME} gitvault help
EOF
}

# Read CLI options, shows gitvault level options
cli__gitvault_options() {
  while [[ -n "${1:-}" ]]; do
    # : "parse-opt-start"
    case "$1" in
    -h | --help | help)
      : ",Show help"
      clish_help cli__gitvault
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

cli__gitvault() {
  : "COMMAND,Manage gitvaults"

  # Set default vars
  local msg="Default message"
  local mode="limited"
  local args=

  # Parse args
  clish_parse_opts cli__gitvault "$@"
  set -- "${args[@]}"

  _db_ensure_open

  # Dispatch to sub commands
  clish_dispatch cli__gitvault__ "$@" || _die $?
}

# Basic simple level sub-commands
# ---------------

cli__gitvault__new() {
  : "NAME [ID...],Create new gitvault"
  lib_gitvault_new "$@"
}

cli__gitvault__ls() {
  : ",List gitvaults"

  set -x

  if [[ "$#" -eq 0 ]]; then
    item_list_names gitvault
  else
    item_ident_resources "$1" gitvault
  fi
}

cli__gitvault__rm() {
  : "NAME,Remove subcommand"
  lib_gitvault_rm "$@"
}

cli__gitvault__lock() {
  : "NAME,Close gitvault"
  lib_gitvault_lock "$@"
}

cli__gitvault__unlock() {
  : "NAME [ID...],Open or mount gitvault"
  lib_gitvault_unlock "$@"
}


cli__gitvault__push() {
  : "NAME,Push gitvault in crypt"
  lib_gitvault_push "$@"
}

cli__gitvault__pull() {
  : "NAME [ID...],Pull gitvault from crypt"
  lib_gitvault_pull "$@"
}


APP_ITEMS_KINDS="${APP_ITEMS_KINDS} vault"



# Vault management (internal)
# =================

# List vault names in config
# DEPRECATED, use: item_list_names instead
# vault_list_names() {
#   _dir_db dump "vault." |
#     sed 's/^vault.//;s/\..*//' |
#     sort -u
# }

# List all vault that belong to ident
# vault_list_names_for_id() {
#   local ident=$1

#   _dir_db dump "vault." |
#     grep "=$ident$" |
#     sed 's/^vault.//;s/\..*//' |
#     sort -u
# }

# List opened vaults
# lib_vault_opened_names() {
#   local vaults=$(item_list_names $kind)
#   for name in $vaults; do
#     [[ -d "$APP_VAULTS_DIR/$name" ]] && echo "$name"
#   done
# }

# Check if a vault exists
# DEPRECATED, use: item_assert_exists instead
# vault_assert_exists() {
#   local name=$1
#   item_list_names $kind | grep -q "^$name$"
#   return $?
# }

# Vault management (public)
# =================

# Create an new opened vault
lib_vault_new() {
  local vault_name=$1
  shift 1
  local idents=${@:-}

  # Create new item
  item_new vault "$vault_name" "$idents"

  # Create vault
  local vault_dest="$APP_VAULTS_DIR/$vault_name"
  ensure_dir "$vault_dest"
  echo "Hello world" >>"$vault_dest/README.md"

  _log INFO "New vault created in: $vault_dest"

}



# Push changes and clean
lib_vault_lock() {
  local vault_name=$1

  local ret=''
  item_push vault "$vault_name"
  ret=$?

  # Validate
  [[ "$ret" -eq "0" ]] ||
    _die "$ret" "Some errors happened, did not remove local data!"

  # Cleanup
  _exec rm -rf "$APP_VAULTS_DIR/$vault_name"
  _log INFO "Vault '$vault_name' closed successfully."

}

# Decrypt and open vault
lib_vault_unlock() {
  local vault_name=$1
  shift 1
  local ident=${@:-}

  item_pull vault "$vault_name" "$ident"
}







# CLI Vault Commands
# =================

# Display help message
cli__vault_usage() {
  cat <<EOF
${APP_NAME}: Manage vaults (Subcommand example)

usage: ${APP_NAME} vault [OPTS] add NAME
       ${APP_NAME} vault [OPTS] rm NAME
       ${APP_NAME} vault help
EOF
}

# Read CLI options, shows vault level options
cli__vault_options() {
  while [[ -n "${1:-}" ]]; do
    # : "parse-opt-start"
    case "$1" in
    -h | --help | help)
      : ",Show help"
      clish_help cli__vault
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

cli__vault() {
  : "COMMAND,Manage vaults"

  # Set default vars
  local msg="Default message"
  local mode="limited"
  local args=

  # Parse args
  clish_parse_opts cli__vault "$@"
  set -- "${args[@]}"

  _db_ensure_open

  # Dispatch to sub commands
  clish_dispatch cli__vault__ "$@" || _die $?
}

# Basic simple level sub-commands
# ---------------

cli__vault__new() {
  : "NAME [ID...],Create new vault"
  lib_vault_new "$@"
}

cli__vault__ls() {
  : ",List vaults"

  if [[ "$#" -eq 0 ]]; then
    item_list_names vault
  else
    item_ident_resources "$1" vault
  fi
}

cli__vault__rm() {
  : "NAME,Remove subcommand"
  item_rm vault "$@"
}

cli__vault__lock() {
  : "NAME,Close vault"
  lib_vault_lock "$@"
}

cli__vault__unlock() {
  : "NAME [ID...],Open or create vault"
  lib_vault_unlock "$@"
}


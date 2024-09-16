
APP_ITEMS_KINDS="${APP_ITEMS_KINDS} vault"


# vault Hooks
# =================


lib_vault_hook__pull_post ()
{
    # Delete existing content, so deleted files are not re-propagated
    if $APP_FORCE; then
      _log WARN "Local changes in '$vault_dir' will be lost after update"
      rm -rf "$vault_dir"
    else
      _log DEBUG "Local changes in '$vault_dir' are kept, deleted files may reappear. Use '-f' to delete first."
    fi
}

lib_vault_hook__lock_final () {

  _exec rm -rf "$APP_VAULTS_DIR/$vault_name"

}

lib_vault_hook__new_final () {

  # Create vault
  local vault_dest="$APP_VAULTS_DIR/$vault_name"
  ensure_dir "$vault_dest"
  echo "Hello world" >>"$vault_dest/README.md"

  _log INFO "New vault created in: $vault_dest"

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
    # -a | --all)
    #   : ",Select all"
    #   mode=all
    #   shift
    #   ;;
    # -m | --message)
    #   : "MSG,Define message"
    #   [[ -n "${2:-}" ]] || _die 1 "Missing message"
    #   msg=$2
    #   shift 2
    #   ;;
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
#   local msg="Default message"
#   local mode="limited"
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
  local vault_name=$1
  shift 1
  local idents=${@:-}

  # Create new item
  item_new vault "$vault_name" "$idents"
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
  local vault_name=$1
  item_push vault "$vault_name"
}

cli__vault__unlock() {
  : "NAME [ID...],Open or create vault"
  local vault_name=$1
  shift 1
  local ident=${@:-}

  item_pull vault "$vault_name" "$ident"
}


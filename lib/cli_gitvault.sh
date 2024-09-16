

APP_ITEMS_KINDS="${APP_ITEMS_KINDS} gitvault"


# gitvault Hooks
# =================

lib_gitvault_hook__push_pre ()
{
    vault_dir="$APP_SPOOL_DIR/$vault_name"
}

lib_gitvault_hook__push_post ()
{
    local target_dir="$APP_VAULTS_DIR/$vault_name"
    if [[ -d "$target_dir" ]]; then
      _log DEBUG "Push local change to gitvault"
      _exec git -C "$target_dir" push #2>/dev/null
    else
      _log DEBUG "Skip git push because vault not mounted"
    fi
}

lib_gitvault_hook__push_final ()
{
  _exec rm -rf "$APP_SPOOL_DIR/$vault_name"
  _exec rm -rf "$APP_VAULTS_DIR/$vault_name"
}


lib_gitvault_hook__pull_pre ()
{
    vault_dir="$APP_SPOOL_DIR/$vault_name"
}


lib_gitvault_hook__pull_final ()
{
    local target_dir="$APP_VAULTS_DIR/$vault_name"

    if [[ -d "$target_dir" ]]; then
      _log DEBUG "Pull from local remote"
      _exec git -C "$target_dir" pull --rebase >/dev/null
    else
      _log DEBUG "Clone from local remote"
      ensure_dir "$target_dir"
      _exec git clone "$APP_SPOOL_DIR/$vault_name" "$target_dir" >/dev/null
    fi
}


lib_gitvault_hook__rm_final ()
{
  # Clean spool
  local repo_spool="$APP_SPOOL_DIR/$vault_name"
  [[ ! -e "$repo_spool" ]] || _exec rm -rf "$repo_spool"

}

lib_gitvault_hook__new_final ()
{
  # Create git spool
  local repo_spool="$APP_SPOOL_DIR/$vault_name"
  git init --bare "$repo_spool"

  # Create vault
  local vault_dest="$APP_VAULTS_DIR/$vault_name"
  git clone "$repo_spool" "$vault_dest" 2>/dev/null

  _log INFO "New gitvault created in: $vault_dest"

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

cli__gitvault() {
  : "COMMAND,Manage gitvaults"

  # Set default vars
#   local msg="Default message"
#   local mode="limited"
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
  local vault_name=$1
  shift 1
  local idents=${@:-}

  # Create new item
  item_new gitvault "$vault_name" "$idents"
}

cli__gitvault__ls() {
  : ",List gitvaults"

  if [[ "$#" -eq 0 ]]; then
    item_list_names gitvault
  else
    item_ident_resources "$1" gitvault
  fi
}

cli__gitvault__rm() {
  : "NAME,Remove subcommand"
  local vault_name=$1
  item_rm gitvault "$vault_name"
}

cli__gitvault__lock() {
  : "NAME,Close gitvault"
  local vault_name=$1
  item_push gitvault "$vault_name"
}

cli__gitvault__unlock() {
  : "NAME [ID...],Open or mount gitvault"
  local vault_name=$1
  shift 1
  local ident=${@:-}
  item_pull gitvault "$vault_name" "$ident"
}

cli__gitvault__push() {
  : "NAME,Push gitvault in crypt"
  local vault_name=$1
  item_push gitvault "$vault_name"
}

cli__gitvault__pull() {
  : "NAME [ID...],Pull gitvault from crypt"
  item_pull gitvault "$@"
}

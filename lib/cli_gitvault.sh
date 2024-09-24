

APP_ITEMS_KINDS="${APP_ITEMS_KINDS} gitvault"


# gitvault Hooks
# =================

lib_gitvault_hook__push_init ()
{
    vault_dir="$APP_SPOOL_DIR/$vault_name"
}

lib_gitvault_hook__push_pre ()
{
    local target_dir="$APP_VAULTS_DIR/$vault_name"
    local repo_dir="../.spool/$vault_name"
    
    # if [[ ! -d "$repo_dir" ]]; then
    #     _log INFO "Autocreating empty gitvault bare repo"
    #   _exec git init --bare "$repo_dir"
    # fi


    if [[ -d "$target_dir" ]]; then
      _log DEBUG "Push local change to gitvault"
      _exec git -C "$target_dir" push #2>/dev/null
    else
      _log DEBUG "Skip git push because vault not mounted"
    fi
}

lib_gitvault_hook__lock_post ()
{
  _exec rm -rf "$APP_SPOOL_DIR/$vault_name"
  _exec rm -rf "$APP_VAULTS_DIR/$vault_name"
}


lib_gitvault_hook__pull_init ()
{
    vault_dir="$APP_SPOOL_DIR/$vault_name"
}


lib_gitvault_hook__pull_post ()
{
    local target_dir="$APP_VAULTS_DIR/$vault_name"
    local repo_dir="$APP_SPOOL_DIR/$vault_name"
    local repo_dir_rel="../.spool/$vault_name"

    if [[ ! -d "$repo_dir" ]]; then
        _log INFO "Autocreating empty gitvault bare repo"
      _exec git init --bare "$repo_dir"
    fi

    if [[ -d "$target_dir/.git" ]]; then
      _log DEBUG "Pull from local remote"
      (
        cd "$target_dir"
        _exec git -C "$target_dir" pull --rebase >/dev/null
      )
    else
      _log DEBUG "Clone from local remote"
      ensure_dir "$target_dir"
      _exec git clone "$repo_dir_rel" "$target_dir" >/dev/null
    fi

# set +x
}


lib_gitvault_hook__rm_final ()
{
  # Clean spool
  local repo_spool="$APP_SPOOL_DIR/$vault_name"
  [[ ! -e "$repo_spool" ]] || _exec rm -rf "$repo_spool"

}

lib_gitvault_hook__new_post ()
{
  # Create git spool
  local repo_spool="$APP_SPOOL_DIR/$vault_name"
  local repo_dir_rel="../.spool/$vault_name"
  git init --bare "$repo_spool"

  # Create vault
  local vault_dest="$APP_VAULTS_DIR/$vault_name"
  git clone "$repo_dir_rel" "$vault_dest" 2>/dev/null

  # Create content
  local target="README.md"
  if [[ -f "$target" ]]; then
    echo "# Welcome on $vault_name" >  "$vault_dest/$target"
    _exec git -C "$vault_dest" add -m "add: new $kind $vault_name"  "$target"
    _exec git -C "$vault_dest" push origin
  fi

#   touch 
#   git clone "$repo_spool" "$vault_dest" 2>/dev/null

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

  _db_is_open || _die 1 "You must unlock cryptobox first"

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

{
  if [[ "$#" -eq 0 ]]; then
    item_list_names gitvault
  else
    item_ident_resources "$1" gitvault
  fi
} || _log INFO "No available gitvaults"
}

cli__gitvault__rm() {
  : "NAME,Remove subcommand"
  local vault_name=$1
  item_rm gitvault "$vault_name"
}

cli__gitvault__lock() {
  : "NAME,Close gitvault"
  local vault_name=$1
  item_lock gitvault "$vault_name"
}

cli__gitvault__unlock() {
  : "NAME [ID...],Open or mount gitvault"
  local vault_name=$1
  shift 1
  local ident=${@:-}
  item_unlock gitvault "$vault_name" "$ident"
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


APP_ITEMS_KINDS="${APP_ITEMS_KINDS} vault"


# vault Hooks
# =================

lib_vault_hook__load ()
{
  export _VAULT_IS_GIT=false

  if [[ -d "$_VAULT_DIR/.git" ]] && has_commits "$_VAULT_DIR"; then
    _VAULT_IS_GIT=true
  fi

}


lib_vault_hook__pull_pre ()
{
  # Check if git directory exists
  if $_VAULT_IS_GIT ; then

    export GIT_WORKTREE=$_VAULT_DIR
    local ref_br=main
    local local_br=$(git_curent_branch)
    local br_name="work-$APP_INSTANCE"
    export RESTORE_STASH=false
    export OLD_BRANCH=$local_br

    _log INFO "Local branch name: $br_name"

    # Check if workspace is clean, or stash it
    if [[ -n "$(git -C "$_VAULT_DIR" status -s)" ]]; then
      _log WARN "Stashing untracked changes in $_VAULT_NAME"
      git -C "$_VAULT_DIR" stash
      RESTORE_STASH=true
    fi

    # Delete local branch if it exists
    if git_branch_exists "$br_name"; then
      _log ERROR "Unmerged changes in $_VAULT_NAME from branch, please delete: $br_name"
      return 1
      # _log DEBUG "Delete existing reserved branch: $br_name"
      # _exec git -C "$_VAULT_DIR" branch -D "$br_name"
    fi

    # Ensure we are on main
    if [[ "$local_br" != "$ref_br" ]]; then
      _exec git -C "$_VAULT_DIR" checkout "$ref_br"
    fi

    # Create local copy of main branch
    _exec git -C "$_VAULT_DIR" branch "$br_name" "$local_br"
    unset GIT_WORKTREE
  fi

}


lib_vault_hook__pull_post ()
{
  if $_VAULT_IS_GIT ; then

    export GIT_WORKTREE=$_VAULT_DIR
    local ref_br=main
    local curr_br=$(git_curent_branch)
    local br_name="work-$APP_INSTANCE"

    _log DEBUG "Trying to rebase $ref_br from $br_name ..."
    # Checkout correct main branch
    if [[ "$curr_br" != "$ref_br" ]]; then
      git -C "$_VAULT_DIR" checkout "$ref_br"
    fi

    # Try to rebase first from local copy
    if _exec git -C "$_VAULT_DIR" rebase -Xtheirs "$ref_br"; then
      _log INFO "Vault rebased from $ref_br"
    else
      # Failed to rebase, so cleanup
      _exec git -C "$_VAULT_DIR" rebase --abort

      _log DEBUG "Trying to merge from $ref_br ... (ours)"
      # Try then to merge changes
      if _exec git -C "$_VAULT_DIR" merge -m "Merge from $br_name" "$br_name" -Xtheirs; then
        _log INFO "Vault merged from $br_name"
        _exec git -C "$_VAULT_DIR" branch -D  "$br_name"
        _exec git -C "$_VAULT_DIR" checkout .
      else
        _exec git -C "$_VAULT_DIR" merge --abort
        _log WARN "Vault diverged from $br_name, please fix yourself!"
      fi
    fi

    # Go back to last branch
    if [[ "$ref_br" != "$OLD_BRANCH" ]]; then
      git -C "$_VAULT_DIR" checkout "$OLD_BRANCH" || { 
        _log ERROR "Failed to go back on previous branch: $OLD_BRANCH"
        RESTORE_STASH=false
      }
    fi

    # Retore unstaged changes
    if $RESTORE_STASH ; then
      _log DEBUG "Restore stash"
      git  -C "$_VAULT_DIR" stash pop
    fi

    unset GIT_WORKTREE
  fi

}


lib_vault_hook__push_pre ()
{
  if $_VAULT_IS_GIT ; then
    export GIT_WORKTREE=$_VAULT_DIR
    local local_br=$(git_curent_branch)
    local br_name="work-$APP_INSTANCE"

    export ref_br=main
    export RESTORE_STASH=false
    export OLD_BRANCH=$local_br
    export RESTORE_STASH_PATCH=

    _log INFO "Local branch name: $br_name"

    # Check if workspace is clean, or stash it
    if [[ -n "$(git -C "$_VAULT_DIR" clean -n)" ]]; then
      _log WARN "Saving untracked changes in $_VAULT_NAME"

      
      local tmp_dir=$(mktemp -d --dry-run)
      _exec cp -a "$_VAULT_DIR" "$tmp_dir"
      _exec rm -rf "$tmp_dir/.git"
      RESTORE_STASH_PATCH=$(tar_to_base64 "$tmp_dir")
      _exec rm -rf "$tmp_dir"
    fi

    _exec git clean -f

    if [[ "$local_br" != "$ref_br" ]]; then
      _log INFO "Checking out main before encrypting $_VAULT_DIR"
      _exec git -C "$_VAULT_DIR" checkout "$ref_br"
    fi

    unset GIT_WORKTREE
  fi

}

lib_vault_hook__push_post ()
{
  if $_VAULT_IS_GIT ; then

    # Go back to last branch
    if [[ "$ref_br" != "$OLD_BRANCH" ]]; then
      git -C "$_VAULT_DIR" checkout "$OLD_BRANCH" || { 
        _log ERROR "Failed to go back on previous branch: $OLD_BRANCH"
      }
    fi

    # Retore unstaged changes
    if [[ -n "$RESTORE_STASH_PATCH" ]] ; then
      _log INFO "Restore local data"
      echo "$RESTORE_STASH_PATCH" | untar_from_base64 "$_VAULT_DIR"
    fi
  fi
}

lib_vault_hook__lock_post () {

  _exec rm -rf "$APP_VAULTS_DIR/$_VAULT_NAME"

}

lib_vault_hook__new_post () {

  # Create vault
  git init "$_VAULT_DIR" >/dev/null
  # echo "Hello world" >> "$_VAULT_DIR/README.md"
  _log INFO "New vault created in: $_VAULT_DIR"

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
  local args=

  # Parse args
  clish_parse_opts cli__vault "$@"
  set -- "${args[@]}"

  _db_is_open || _die 1 "You must unlock cryptobox first"

  # Dispatch to sub commands
  clish_dispatch cli__vault__ "$@" || _die $?
}

# Basic simple level sub-commands
# ---------------

cli__vault__new() {
  : "NAME [ID...],Create new vault"
  # Create new item
  item_new "$1" "$2"
}

cli__vault__ls() {
  : ",List vaults"

  if [[ "$#" -eq 0 ]]; then
    item_list_names2
  else
    item_ident_resources "$1" vault
  fi
}

cli__vault__rm() {
  : "NAME,Remove subcommand"
  item_rm "${1:-$APP_DEFAULT_VAULTS_NAME}"
}

cli__vault__push() {
  : "NAME,Push vault"
  item_push "${1:-$APP_DEFAULT_VAULTS_NAME}"
}

cli__vault__pull() {
  : "NAME [ID...],Open or create vault"
  # local _VAULT_NAME=$1
  # shift 1
  # local ident=${@:-}

  item_pull "${1:-$APP_DEFAULT_VAULTS_NAME}" "${2:-}"
}


cli__vault__lock() {
  : "NAME,Close vault"
  local _VAULT_NAME=$1
  item_lock vault "$_VAULT_NAME"
}

cli__vault__unlock() {
  : "NAME [ID...],Open or create vault"
  local _VAULT_NAME=$1
  shift 1
  local ident=${@:-}

  item_unlock vault "$_VAULT_NAME" "$ident"
}

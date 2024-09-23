
APP_ITEMS_KINDS="${APP_ITEMS_KINDS} vault"


# vault Hooks
# =================


# lib_vault_hook__pull_pre_V1 ()
# {
#     # # Delete existing content, so deleted files are not re-propagated
#     # if $APP_FORCE; then
#     #   _log WARN "Local changes in '$_VAULT_DIR' will be lost after update"
#     #   rm -rf "$_VAULT_DIR"
#     # else
#     #   _log DEBUG "Local changes in '$_VAULT_DIR' are kept, deleted files may reappear. Use '-f' to delete first."
#     # fi

#     # Check if git directory exists
#     if $_VAULT_IS_GIT ; then
#       export GIT_WORKTREE=$_VAULT_DIR
#       local ref_br=main
#       local local_br=$(git_curent_branch)
#       local br_name="work-$APP_INSTANCE"
#       _log INFO "Local branch name: $br_name"

#       set -x

#       if [[ "$local_br" != "$br_name" ]]; then
#         if git_branch_exists "$br_name"; then
#           git -C "$_VAULT_DIR" checkout "$br_name"
#         else
#           git -C "$_VAULT_DIR" checkout -b "$br_name" "$local_br"
#         fi
#       else
#         _log INFO "Already on the correct branch"
#       fi

#       # Do the merge
#       if git -C "$_VAULT_DIR" rebase "$ref_br"; then
#         _log INFO "Vault rebased from $ref_br"
#       else 
#         git -C "$_VAULT_DIR" rebase --abort

#         if git -C "$_VAULT_DIR" merge "$ref_br" -Xtheirs; then
#           _log INFO "Vault merged from $ref_br"
#         else
#           git -C "$_VAULT_DIR" merge --abort
#           _log WARN "Vault diverged from $ref_br, please fix yourself!"
#         fi
#       fi

#       set +x
#       unset GIT_WORKTREE

#     fi
#     # set +x
# }





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
  # set +x

}


lib_vault_hook__pull_post ()
{
  if $_VAULT_IS_GIT ; then
    set -x
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

# Function to tar a directory and store as base64 in a variable
tar_to_base64() {
    local dir_path="$1"
    
    if [ ! -d "$dir_path" ]; then
        echo "Error: Directory not found: $dir_path" >&2
        return 1
    fi
    
    local base64_content
    # base64_content=$(tar -czf - -C "$(dirname "$dir_path")" "$(basename "$dir_path")" | base64 -w 0)
    base64_content=$(tar -czf - -C "$dir_path" . | base64 -w 0)
    
    # echo "$base64_content" | base64 -d | tar -tzf -  >&2

    # Use eval to create a variable with the given name
    echo "$base64_content"
}

# Function to untar a base64-encoded tarball stored in a variable
untar_from_base64() {
    local output_dir="$1"
    
    if [ ! -d "$output_dir" ]; then
        mkdir -p "$output_dir"
    fi
    
    cat - | base64 -d | tar -xzf - -C "$output_dir"
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
    # if [[ -n "$(git -C "$_VAULT_DIR" status -s)" ]]; then
    if [[ -n "$(git -C "$_VAULT_DIR" clean -n)" ]]; then
      _log WARN "Saving untracked changes in $_VAULT_NAME"

      
      local tmp_dir=$(mktemp -d --dry-run)
      _exec cp -a "$_VAULT_DIR" "$tmp_dir"
      _exec rm -rf "$tmp_dir/.git"
      RESTORE_STASH_PATCH=$(tar_to_base64 "$tmp_dir")
      _exec rm -rf "$tmp_dir"

      # _log WARN "Stashing untracked changes in $_VAULT_NAME"

      # git -C "$_VAULT_DIR" add .
      # git -C "$_VAULT_DIR" stash
      # RESTORE_STASH=true
      # RESTORE_STASH_PATCH=$(git -C "$_VAULT_DIR" show -p)
      # git -C "$_VAULT_DIR" stash drop
    fi

    _exec git clean -f

    if [[ "$local_br" != "$ref_br" ]]; then
      _log INFO "Checking out main before encrypting $_VAULT_DIR"
      _exec git -C "$_VAULT_DIR" checkout "$ref_br"
    fi

    # _exec git -C "$_VAULT_DIR" ll

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
        # RESTORE_STASH=false
      }
    fi

    # Retore unstaged changes
    if [[ -n "$RESTORE_STASH_PATCH" ]] ; then
      _log INFO "Restore local data"
      echo "$RESTORE_STASH_PATCH" | untar_from_base64 "$_VAULT_DIR"
      # git  -C "$_VAULT_DIR" stash apply <<<"$RESTORE_STASH_PATCH"
    fi
  fi
}

lib_vault_hook__lock_post () {

  _exec rm -rf "$APP_VAULTS_DIR/$_VAULT_NAME"

}

lib_vault_hook__new_post () {

  # Create vault
  # local vault_dest="$APP_VAULTS_DIR/$_VAULT_NAME"
  # ensure_dir "$vault_dest"
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
  # local _VAULT_NAME=$1
  # shift 1
  # local idents=${@:-}

  # Create new item
  item_new "$1" "$2"
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

cli__vault__push() {
  : "NAME,Push vault"
  local _VAULT_NAME=$1
  item_push "$_VAULT_NAME"
}

cli__vault__pull() {
  : "NAME [ID...],Open or create vault"
  local _VAULT_NAME=$1
  shift 1
  local ident=${@:-}

  item_pull "$_VAULT_NAME" "$ident"
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

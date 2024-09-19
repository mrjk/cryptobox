
APP_ITEMS_KINDS="${APP_ITEMS_KINDS} vault"


# vault Hooks
# =================


# lib_vault_hook__pull_pre_V1 ()
# {
#     # # Delete existing content, so deleted files are not re-propagated
#     # if $APP_FORCE; then
#     #   _log WARN "Local changes in '$vault_dir' will be lost after update"
#     #   rm -rf "$vault_dir"
#     # else
#     #   _log DEBUG "Local changes in '$vault_dir' are kept, deleted files may reappear. Use '-f' to delete first."
#     # fi

#     # Check if git directory exists
#     if [[ -d "$vault_dir/.git" ]]; then
#       export GIT_WORKTREE=$vault_dir
#       local ref_br=main
#       local local_br=$(git_curent_branch)
#       local br_name="work-$APP_INSTANCE"
#       _log INFO "Local branch name: $br_name"

#       set -x

#       if [[ "$local_br" != "$br_name" ]]; then
#         if git_branch_exists "$br_name"; then
#           git -C "$vault_dir" checkout "$br_name"
#         else
#           git -C "$vault_dir" checkout -b "$br_name" "$local_br"
#         fi
#       else
#         _log INFO "Already on the correct branch"
#       fi

#       # Do the merge
#       if git -C "$vault_dir" rebase "$ref_br"; then
#         _log INFO "Vault rebased from $ref_br"
#       else 
#         git -C "$vault_dir" rebase --abort

#         if git -C "$vault_dir" merge "$ref_br" -Xtheirs; then
#           _log INFO "Vault merged from $ref_br"
#         else
#           git -C "$vault_dir" merge --abort
#           _log WARN "Vault diverged from $ref_br, please fix yourself!"
#         fi
#       fi

#       set +x
#       unset GIT_WORKTREE

#     fi
#     # set +x
# }


lib_vault_hook__pull_pre ()
{


    # Check if git directory exists
    if [[ -d "$vault_dir/.git" ]]; then
      set -x

      export GIT_WORKTREE=$vault_dir
      local ref_br=main
      local local_br=$(git_curent_branch)
      local br_name="work-$APP_INSTANCE"
      export RESTORE_STASH=false
      export OLD_BRANCH=$local_br

      _log INFO "Local branch name: $br_name"

      # Check if workspace is clean
      if [[ -n "$(git -C "$vault_dir" status -s)" ]]; then
        _log WARN "Stashing untracked changes in $vault_name"
        git -C "$vault_dir" stash
        RESTORE_STASH=true
      fi



      # set -x
      if git_branch_exists "$br_name"; then
        _log WARN "Delete existing branch: $br_name"
        _exec git -C "$vault_dir" branch -D  "$br_name"
      fi

      # Ensure we are on main
      _exec git -C "$vault_dir" checkout "$ref_br"

      # Create local copy of branch
      _exec git -C "$vault_dir" branch "$br_name" "$local_br"

      unset GIT_WORKTREE

    fi
    set +x
}


lib_vault_hook__pull_post ()
{
    if [[ -d "$vault_dir/.git" ]]; then
      set -x
      export GIT_WORKTREE=$vault_dir
      local ref_br=main
      local curr_br=$(git_curent_branch)
      local br_name="work-$APP_INSTANCE"
      _log INFO "Local branch name: $br_name"

    # set -x


      # git -C "$vault_dir" pull

      # # Remove existing files
      # while read -r file ; do
      #   [[ -n "$file" ]] || continue
      #   local target="$vault_dir/$file"
      #   _log WARN "Remove file: $target"
      #   _exec rm "$target"
      # done <<<$(git -C "$vault_dir" ls-tree -r --name-only "$br_name")
      # # echo DOOOOOOOOOOOOOOONE

      _log INFO "Trying to rebased from $ref_br ..."


      # Checkout correct branch
      if [[ "$curr_br" != "$ref_br" ]]; then
        git -C "$vault_dir" checkout "$ref_br"
      fi

      # Try to rebase first
      if _exec git -C "$vault_dir" rebase -Xtheirs "$ref_br"; then
        _log INFO "Vault rebased from $ref_br"
      else
        # Cleanup
        _exec git -C "$vault_dir" rebase --abort

        _log INFO "Trying to merge from $ref_br ... (ours)"
        # Try then to merge changes
        if _exec git -C "$vault_dir" merge -m "Merge from $br_name" "$br_name" -Xtheirs; then
          _log INFO "Vault merged from $br_name"
          _exec git -C "$vault_dir" branch -D  "$br_name"
          _exec git -C "$vault_dir" checkout .
        else
          _exec git -C "$vault_dir" merge --abort
          _log WARN "Vault diverged from $br_name, please fix yourself!"
        fi
      fi

      # Go back to last branch
      if [[ "$ref_br" != "$OLD_BRANCH" ]]; then
        git -C "$vault_dir" checkout "$OLD_BRANCH"
      fi

      # Retore unstaged changes
      if $RESTORE_STASH ; then
        _log WARN "Restore stash"
        git  -C "$vault_dir" stash pop
      fi


      set +x
      # if [[ "$local_br" != "$br_name" ]]; then
      #   if git_branch_exists "$br_name"; then
      #     git -C "$vault_dir" checkout "$br_name"
      #   else
      #     git -C "$vault_dir" checkout -b "$br_name" "$local_br"
      #   fi
      # else
      #   _log INFO "Already on the correct branch"
      # fi

      unset GIT_WORKTREE


    fi
  set +x
}



# lib_vault_hook__pull_post ()
# {

# }

lib_vault_hook__push_pre ()
{

  if [[ -d "$vault_dir/.git" ]]; then
      export GIT_WORKTREE=$vault_dir
      local ref_br=main
      local curr_br=$(git_curent_branch)
      local br_name="work-$APP_INSTANCE"
      _log INFO "Local branch name: $br_name"

      # git merge main -Xours
      # set -x
      if [[ "$curr_br" != "$ref_br" ]]; then
        _log INFO "Checking out main"
        _exec git -C "$vault_dir" checkout "$ref_br"
      fi


      unset GIT_WORKTREE

  fi
  set +x

}


lib_vault_hook__lock_post () {

  _exec rm -rf "$APP_VAULTS_DIR/$vault_name"

}

lib_vault_hook__new_post () {

  # Create vault
  local vault_dest="$APP_VAULTS_DIR/$vault_name"
  # ensure_dir "$vault_dest"
  git init "$vault_dest"
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


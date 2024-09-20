
# CLI libraries
# =================

# Validate log level pass aginst limit
_log_validate_level ()
{
  local level=$1
  local limit_level=${2:-${APP_LOG_SCALE%%:*}}
  
  if [[ ! ":${APP_LOG_SCALE#*$limit_level:}:$limit_level:" =~ :"$level": ]]; then
    if [[ ! ":${APP_LOG_SCALE}" =~ :"$level": ]]; then
      >&2 printf "%s\n" "  BUG: Unknown log level: $level"
    fi
    return 1
  fi
}

# Logging support, with levels
_log() {
  # old_setting=${-//[^x]/}; set +x

  local level="${1:-DEBUG}"
  shift 1 || true

  # Check log level filter
  _log_validate_level "$level" "${APP_LOG_LEVEL:-}" || return 0

  local msg=${*}
  if [[ "$msg" == '-' ]]; then
    msg="$(cat -)"
  fi
  while read -r -u 3 line; do
    >&2 printf "%6s: %s\\n" "$level" "${line:- }"
  done 3<<<"$msg"

  if [[ -n "${old_setting-}" ]]; then set -x; else set +x; fi
}

# Terminate all with error message and rc code
_die() {
  set +x
  local rc=${1:-1}
  shift 1 || true
  local msg="${*:-}"
  local prefix=QUIT
  [[ "$rc" -eq 0 ]] || prefix=DIE
  if [[ -z "$msg" ]]; then
    [ "$rc" -ne 0 ] || exit 0
    _log "$prefix" "Program terminated with error: $rc ($$)"
  else
    _log "$prefix" "$msg ($$)"
  fi

  # Remove EXIT trap and exit nicely
  trap '' EXIT
  exit "$rc"
}

# Run command with dry mode support
_exec() {
  local cmd=("$@")
  if ${APP_DRY:-false}; then
    _log DRY "  | ${cmd[@]}"
  else
    _log RUN "  | ${cmd[@]}"
    "${cmd[@]}"
  fi
}

# Dump all application vars (debug)
# shellcheck disable=SC2120 # Argument is optional by default
_dump_vars() {
  local prefix=${1:-APP_}
  declare -p | grep " .. $prefix" >&2 || {
    >&2 _log WARN "No var starting with: $prefix"
  }
}

# Ensure a program is available
_check_bin() {
  local cmd cmds="${*:-}"
  for cmd in $cmds; do
    command -v "$1" >&/dev/null || return 1
  done
}

# Internal helper to show bash traces (debug)
# shellcheck disable=SC2120 # Argument is optional by default
_sh_trace() {
  local msg="${*}"

  (
    >&2 printf "%s\n" "TRACE: line, function, file"
    for i in {0..10}; do
      trace=$(caller "$i" 2>&1 || true)
      if [ -z "$trace" ]; then
        continue
      else
        printf "%s\n" "$trace"
      fi
    done | tac | head -n -1
    [ -z "$msg" ] || >&2 printf "%s\n" "TRACE: Bash trace: $msg"
  )
}

# Internal function to catch errors
# Usage: trap '_sh_trap_error $? ${LINENO} trap_exit 42' EXIT
_sh_trap_error() {
  local rc=$1
  [[ "$rc" -ne 0 ]] || return 0
  local line="$2"
  local msg="${3-}"
  local code="${4:-1}"
  set +x

  _log ERR "Uncatched bug:"
  _sh_trace # | _log TRACE -
  if [[ -n "$msg" ]]; then
    _log ERR "Error on or near line ${line}: ${msg}; got status ${rc}"
  else
    _log ERR "Error on or near line ${line}; got status ${rc}"
  fi
  exit "${code}"
}


# CLI helpers
# =================

# Dispatch command
clish_dispatch() {
  local prefix=$1
  local cmd=${2-}
  shift 2 || true
  [ -n "$cmd" ] || _die 3 "Missing command name, please check usage"

  if [[ $(type -t "${prefix}${cmd}") == function ]]; then
    "${prefix}${cmd}" "$@"
  else
    _log ERROR "Unknown command for ${prefix%%_?}: $cmd"
    return 3
  fi
}

# Parse command options
# Called function must return an args array with remaining args
clish_parse_opts() {
  local func=$1
  shift
  clish_dispatch "$func" _options "$@"
}

# Read CLI options for a given function/command
# Options must be in a case statement and surounded by
# 'parse-opt-start' and 'parse-opt-stop' strings. Returns
# a list of value separated by ,. Fields are:
clish_help_options() {
  local func=$1
  local data=

  # Check where to look options function
  if declare -f "${func}_options" >/dev/null; then
    func="${func}_options"
    data=$(declare -f "$func")
    data=$(printf "%s\n%s\n" 'parse-opt-start' "$data")
  else
    data=$(declare -f "$func")
  fi

  # declare -f ${func} \
  echo "$data" | awk '/parse-opt-start/,/parse-opt-stop/ {print}' |
    grep --no-group-separator -A 1 -E '^ *--?[a-zA-Z0-9].*)$' |
    sed -E '/\)$/s@[ \)]@@g;s/.*: "//;s/";//' |
    xargs -n2 -d'\n' |
    sed 's/ /,/;/^$/d'
}

# List all available commands starting with prefix
clish_help_subcommands() {
  local prefix=${1:-cli__}
  declare -f |
    grep -E -A 2 '^'"$prefix"'[a-z0-9]*(__[a-z0-9]*)*? \(\)' |
    sed '/{/d;/--/d;s/'"$prefix"'//;s/ ()/,/;s/";$//;s/^  *: "//;' |
    xargs -n2 -d'\n' |
    sed 's/, */,/;s/__/ /g;/,,$/d'
}

# Show help message of a function
clish_help_msg() {
  local func=$1
  clish_dispatch "$func" _usage 2>/dev/null || true
}

# Show cli usage for a given command
clish_help() {
  : ",Show this help"
  local func=${1:-cli}
  local commands='' options='' message='' output=''

  # Help message
  message=$(clish_help_msg $func)

  # Fetch command options
  options=$(
    while IFS=, read -r flags meta desc _; do
      if [ -n "${flags:-}" ]; then
        printf "  %-16s  %-20s  %s\n" "$flags" "$meta" "$desc"
      fi
    done <<<"$(clish_help_options $func)"
  )

  # Fetch sub command informations
  commands=$(
    while IFS=, read -r flags meta desc _; do
      if [ -n "${flags:-}" ]; then
        printf "  %-16s  %-20s  %s\n" "$flags" "$meta" "$desc"
      fi
    done <<<"$(clish_help_subcommands ${func}__)"
  )

  # Display help message
  printf "%s\n" "${message:+$message}
${commands:+
commands:
$commands}
${options:+
options:
$options
}"

  # Append extra infos
  if ! [[ "$func" == *"_"* ]]; then
    cat <<EOF
info:
  author: $APP_AUTHOR ${APP_EMAIL:+<$APP_EMAIL>}
  version: ${APP_VERSION:-0.0.1}-${APP_STATUS:-beta}${APP_DATE:+ ($APP_DATE)}
  license: ${APP_LICENSE:-MIT}
EOF
  fi

}

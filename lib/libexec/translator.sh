#shellcheck shell=sh disable=SC2004,SC2034,SC2119,SC2120,SC2016

# shellcheck source=lib/libexec.sh
. "${SHELLSPEC_LIB:-./lib}/libexec.sh"
use constants trim match_pattern ends_with escape_quote
load grammar

initialize() {
  lineno=0 block_no=0 example_no=1 skip_id=0 error='' focused='' skipped=''
  _block_no=0 _block_no_stack=''
  parameter_count='' parameter_no=0 _parameter_count_stack=''
  parameters_need_example=''
}

finalize() {
  [ "$_block_no_stack" ] || return 0
  syntax_error "unexpected end of file (expecting 'End')"
  lineno=
  while [ "$_block_no_stack" ]; do block_end ""; done
}

read_specfile() {
  eval "{ IFS= read -r $1 || [ \"\$$1\" ]; } && $1=\${$1%\"\$CR\"}" && {
    lineno=$(($lineno + 1))
  }
}

one_line_syntax_check() { :; }

check_filter() {
  escaped_syntax=''
  escape_one_line_syntax escaped_syntax "$1"
  eval "set -- $escaped_syntax"
  if [ $# -gt 0 ]; then
    match_pattern "$1" "$SHELLSPEC_EXAMPLE_FILTER" && return 0
    shift
  fi
  [ "$SHELLSPEC_TAG_FILTER" ] || return 1
  while [ $# -gt 0 ]; do
    case $SHELLSPEC_TAG_FILTER in (*,$1,*) return 0; esac
    case $1 in
      *:*) case $SHELLSPEC_TAG_FILTER in (*,${1%%:*},*) return 0; esac ;;
      *  ) case $SHELLSPEC_TAG_FILTER in (*,$1,*) return 0 ; esac ;;
    esac
    shift
  done
  return 1
}

escape_one_line_syntax() {
  eval="
    set -- \"\$2\" '' ''; \
    while [ \"\$1\" ]; do \
      $1=\${1#?}; \
      case \$3\$1 in \
        \\\$* | \\\`*) set -- \"\$1\" \"\$2\\\\\" '' ;; \
        \'*)  set -- \"\$1\" \"\$2\" q ;; \
        q\'*) set -- \"\$1\" \"\$2\" '' ;; \
      esac; \
      $1=\${1%\"\${$1}\"}; \
      set -- \"\${1#?}\" \"\$2\${$1}\" \"\$3\"; \
    done; \
    $1=\$2
  "
  eval "$eval"
}

is_constant_name() {
  case $1 in ([!A-Z_]*) return 1; esac
  case $1 in (*[!A-Z0-9_]*) return 1; esac
}

is_function_name() {
  case $1 in ([!a-zA-Z_]*) return 1; esac
  case $1 in (*[!a-zA-Z0-9_]*) return 1; esac
}

block_example_group() {
  if [ "$inside_of_example" ]; then
    syntax_error "Describe/Context cannot be defined inside of Example"
    return 0
  fi

  if ! one_line_syntax_check error "$1"; then
    syntax_error "Describe/Context has occurred an error" "$error"
    return 0
  fi

  check_filter "$1" && filter=1

  increase_block_id
  _block_no=$(($_block_no + 1))
  block_no=$_block_no lineno_begin=$lineno
  eval "block_lineno_begin${_block_no}=$lineno"

  eval trans block_example_group ${1+'"$@"'}

  _block_no_stack="$_block_no_stack $_block_no" filter=''
  _parameter_count_stack="$_parameter_count_stack $parameter_no:$parameter_count"
}

block_example() {
  if [ "$inside_of_example" ]; then
    syntax_error "It/Example/Specify/Todo cannot be defined inside of Example"
    return 0
  fi

  parameters_need_example=''

  if ! one_line_syntax_check error "$1"; then
    syntax_error "It/Example/Specify/Todo has occurred an error" "$error"
    return 0
  fi

  check_filter "$1" && filter=1

  increase_block_id
  _block_no=$(($_block_no + 1))
  block_no=$_block_no lineno_begin=$lineno
  eval "block_lineno_begin${block_no}=$lineno"

  eval trans block_example ${1+'"$@"'}

  _block_no_stack="$_block_no_stack $_block_no"
  example_no=$(($example_no + ${parameter_count:-1}))
  _parameter_count_stack="$_parameter_count_stack $parameter_no:$parameter_count"
  filter='' inside_of_example="yes"
}

block_end() {
  if [ -z "$_block_no_stack" ]; then
    syntax_error "unexpected 'End'"
    return 0
  fi

  if [ "$parameters_need_example" ]; then
    syntax_error "Not found any examples. (Missing 'End' of Parameters?)"
    parameters_need_example=''
    return 0
  fi

  decrease_block_id
  block_no=${_block_no_stack##* } lineno_end=$lineno
  eval "block_lineno_end${block_no}=$lineno"
  eval "lineno_begin=\$block_lineno_begin${block_no}"

  if is_in_ranges; then
    enabled=1
    remove_from_ranges
  fi

  eval trans block_end ${1+'"$@"'}
  enabled=''

  _block_no_stack=${_block_no_stack% *}
  parameter_count=${_parameter_count_stack##* }
  parameter_no=${parameter_count%:*}
  parameter_count=${parameter_count#*:}
  _parameter_count_stack=${_parameter_count_stack% *}
  inside_of_example=""
}

x() {
  skipped=1 skip_id=$(($skip_id + 1))
  "$@"
  skipped=''
}

f() {
  focused="focus" filter=1
  "$@"
  focused='' filter=''
}

todo() {
  block_example "$1"
  pending "$1"
  block_end ""
}

statement() {
  if [ -z "$inside_of_example" ]; then
    syntax_error "When/The cannot be defined outside of Example"
    return 0
  fi
  eval trans statement ${1+'"$@"'}
}

control() {
  case $1 in (before|after)
    if [ "$inside_of_example" ]; then
      syntax_error "Before/After cannot be defined inside of Example"
      return 0
    fi
  esac
  eval trans control ${1+'"$@"'}
}

pending() {
  case ${1:-} in (\#*)
    temporary_pending=${1#"#"}
    escape_quote temporary_pending
    trim temporary_pending "$temporary_pending"
    set -- "'# $temporary_pending'"
  esac
  eval trans pending ${1+'"$@"'}
}

skip() {
  skip_id=$(($skip_id + 1))
  case ${1:-} in (\#*)
    temporary_skip=${1#"#"}
    escape_quote temporary_skip
    trim temporary_skip "$temporary_skip"
    set -- "'# $temporary_skip'"
  esac
  eval trans skip ${1+'"$@"'}
}

data() {
  eval trans data_begin ${1+'"$@"'}
  case ${2:-} in
    '' | \#* | \|*)
      trans data_here_begin "$1" "${2:-}"
      line=''
      while read_specfile line; do
        trim line "$line"
        case $line in
          \#\|*) trans data_here_line "$line" ;;
          \#*) ;;
          End | End\ * ) break ;;
          *) syntax_error "Data texts should begin with '#|'"; break ;;
        esac
      done
      trans data_here_end ;;
    \'* | \"*) trans data_text "$2" ;;
    \<*) trans data_file "$2" ;;
    *) trans data_func "$2" ;;
  esac
  eval trans data_end ${1+'"$@"'}
}

text_begin() {
  eval trans text_begin ${1+'"$@"'}
  inside_of_text=1
}

text() {
  case $1 in
    \#\|*) eval trans text ${1+'"$@"'}; return 0 ;;
    *) text_end; return 1 ;;
  esac
}

text_end() {
  eval trans text_end ${1+'"$@"'}
  inside_of_text=''
}

out() {
  eval trans out ${1+'"$@"'}
}

parameters() {
  if [ "$inside_of_example" ]; then
    syntax_error "Parameters cannot be defined inside of Example"
    return 0
  fi
  parameters_need_example=1

  parameter_no=$(($parameter_no + 1))
  trans parameters_begin "$parameter_no"
  #shellcheck disable=SC2145
  "parameters_$@"
  trans parameters_end
}

parameters_generate_code() {
  trans line "$1"
  code="${code}${1}${LF}"
}

parameters_continuation_line() {
  line=$1
  shift
  while ends_with "$line"  "\\"; do
    read_specfile line ||:
    "$@" "$line"
  done
}

parameters_block() {
  while read_specfile line; do
    trim line "$line"
    case $line in (End | End\ * ) break; esac
    case $line in (\#* | '') continue; esac

    trans parameters "$line"
    parameter_count=$(($parameter_count + 1))
    parameters_continuation_line "$line" trans line
  done
}

parameters_dynamic() {
  code=''

  while read_specfile line; do
    trim line "$line"
    case $line in (End | End\ * ) break; esac

    case $line in
      %data | %data\ *)
        line=${line#%data}
        trans parameters "$line"
        line='count=$(($count + 1))'
        ;;
      *) trans line "$line"
    esac
    code="${code}${line}${LF}"
  done

  eval "parameter_count=\$(count=0${LF}${code}echo \"\$count\")"
}

parameters_matrix() {
  code='' nest=0 arguments=''

  while read_specfile line; do
    trim line "$line"
    case $line in (End | End\ * ) break; esac
    case $line in (\#* | '') continue; esac

    nest=$(($nest + 1))
    parameters_generate_code "for shellspex_matrix${nest} in $line"
    arguments="$arguments\"\$shellspex_matrix${nest}\" "
    parameters_continuation_line "$line" parameters_generate_code
    parameters_generate_code "do"
  done

  trans parameters "$arguments"
  code="${code}count=\$((\$count + 1))${LF}"

  while [ $nest -gt 0 ]; do
    parameters_generate_code "done"
    nest=$(($nest - 1))
  done

  eval "parameter_count=\$(count=0${LF}${code}echo \"\$count\")"
}

parameters_value() {
  code=''
  parameters_generate_code "for shellspex_matrix in ${*:-}; do"
  trans parameters "\"\$shellspex_matrix\""
  code="${code}count=\$((\$count + 1))${LF}"
  parameters_generate_code "done"
  eval "parameter_count=\$(count=0${LF}${code}echo \"\$count\")"
}

constant() {
  if [ "$_block_no_stack" ]; then
    syntax_error "Constant should be defined outside of Example Group/Example"
    return 0
  fi

  trim line "$1"
  name=${line%%:*} value=''
  trim value "${line#*:}"
  if is_constant_name "$name"; then
    trans constant "$name" "$value"
    eval "$name=\$value"
  else
    syntax_error "Constant name should match pattern [A-Z_][A-Z0-9_]*"
  fi
}

include() {
  if [ "$inside_of_example" ]; then
    syntax_error "Include cannot be defined inside of Example"
    return 0
  fi

  if ! one_line_syntax_check error "$1"; then
    syntax_error "Include has occurred an error" "$error"
    return 0
  fi

  eval trans include ${1+'"$@"'}
}

with_function() {
  trans with_function "$1"
  shift
  "$@"
}

is_in_range() {
  case $1 in
    @*) [ "$block_id" = "${1#@}" ] ;;
    *) [ "$lineno_begin" -le "$1" ] && [ "$1" -le "$lineno_end" ] ;;
  esac
}

is_in_ranges() {
  [ "${ranges:-}" ] || return 1
  eval "set -- $ranges"
  while [ $# -gt 0 ]; do
    is_in_range "$1" && return 0
    shift
  done
  return 1
}

remove_from_ranges() {
  eval "set -- $ranges"
  ranges=''
  while [ $# -gt 0 ]; do
    is_in_range "$1" || ranges="$ranges$1 "
    shift
  done
}

translate() {
  block_id='' inside_of_example='' inside_of_text='' work=''
  while read_specfile line; do
    while ends_with "$line" "\\"; do
      read_specfile work ||:
      line="${line}${LF}${work}"
    done
    trim work "$line"

    [ "$inside_of_text" ] && text "$work" && continue

    dsl=${work%% *} rest=''
    trim rest "${work#"$dsl"}"
    mapping "$dsl" "$rest" || trans line "$line"
  done
}

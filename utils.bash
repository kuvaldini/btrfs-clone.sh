#!/usr/bin/env bash

# shellcheck disable=SC2329  ## suppress: function never invoked


##
## author: Ian Kuvaldini github.com/kuvaldini
## distributed under MIT License, https://opensource.org/licenses/MIT
## project_page: https://gitlab.com/kuvaldini/utils.bash
## todo move to https://github.com/kuvaldini/utils.bash
##

##
## DOWNLOAD:
##   curl https://raw.githubusercontent.com/kuvaldini/utils.bash/main/utils.bash -LsSf
##   curl https://gitlab.com/kuvaldini/utils.bash/-/raw/main/utils.bash -LsSf
## USAGE:
##   source utils.bash
##   source $(dirname "$( readlink -f "${BASH_SOURCE[0]}" )")
##

set -eETuo errexit -o nounset -o pipefail #-o errtrace -o functrace
shopt -s expand_aliases lastpipe #gnu_errfmt globstar huponexit inherit_errexit localvar_inherit

#[[ ${BASH_SOURCE:-} != "" ]] && {
#   BASH_SOURCE=( EMPTY_BASH_SOURCE )
#}

#export PS4='+ $(date "+%F_%T") ${FUNCNAME[0]:-NOFUNC}() $BASH_SOURCE:${BASH_LINENO[0]} +  '  ## From https://stackoverflow.com/a/22617858
export PS4=$'+\e[33m ${BASH_SOURCE[0]:-nofile}:${BASH_LINENO[0]:-noline} ${FUNCNAME[0]:-nofunc}()\e[0m  '

##
## DEFAULT VARIABLES
##
USE_STACKTRACE=1
unset pre

var_is_set(){
   declare -rn var=$1
   ! test -z ${var+x}
}
var_is_set_not_empty(){
   declare -rn var=$1
   ! test -z ${var:+x}
}
var_is_unset(){
   declare -rn var=$1
   test -z ${var+x}
}
var_is_unset_or_empty(){
   declare -rn var=$1
   test -z ${var:+x}
}

[[ ${BASH_SOURCE:-} != "" ]] && 
   SRCDIR="$(realpath $(dirname "${BASH_SOURCE[-1]}"))"

is_sourced(){
   [[ "${BASH_SOURCE[0]}" != "${0}" ]]
}

if test -t 1 ;then
   msgcolor=$'\e[1;37m'
   msgnocol=$'\e[0m'
else
   msgcolor=$'\e[1;37m'
   msgnocol=$'\e[0m'
fi
if test -t 2 ;then
   :;
fi

function colordbg {
   if test -t 2 ;then
      echo $'\e[0;36m'
   fi
}

function echomsg { 
   echo >&2 $'\e[1;37m'"$*"$'\e[0m'; 
}
function echoerr { 
   >&2 echo $'\e[0;31m'"ERR  $*"$'\e[0m'; 
}
readonly -f echomsg echoerr
# echoerr(){
#    echo >&2 "$@"
# }
echoinfo(){
   echo >&2 "$@"
}
caterr(){
   cat >&2 "$@"
}
fatalerr(){
   echoerr "$@"
   exit 2
}
errreturn(){
   echoerr "$@"
   return 2
}
caterrred(){
   # cat "$@" |
   surround $'\e[0;31m' $'\e[0m' >&2
}

alias die=fatalerr


# shellcheck disable=SC2120
prepend(){
   sed "s,^,$*,"
}
append(){
   sed "s,$,$*,"
}
surround(){
   sed -es,^,"$1", -es,$,"$2",
}

## Execute only for debug purposes command
if var_is_set DEBUG  &&  (( DEBUG != 0 ))  ;then
   function debug  { "$@" | catdbg; }
else
   function debug  { : ; }  ## do nothing
fi

if [[ ${DEBUG:=0} != 0 ]]  ;then
   #shopt -s extdebug
   function echodbg  { >&2 echo $'\e[0;36m'"${pre:-DBG}  $*"$'\e[0m'; }
   # shellcheck disable=SC2120  ## arguments to cat are optional
   function catdbg   { >&2 echo $'\e[0;36m'; cat "$@"; echo $'\e[0m'; }
else
   function echodbg  { :; }  ## do nothing
   function catdbg  { :; }  ## do nothing
fi
if var_is_unset NOINFO  ||  [[ $NOWARN == 0 ]]  ;then
   function echoinfo { >&2 echo $'\e[0;37m'"INFO $*"$'\e[0m'; }
else
   function echoinfo { :; }  ## do nothing
fi
if var_is_unset NOWARN  ||  [[ $NOWARN == 0 ]]  ;then
   function echowarn { >&2 echo $'\e[0;33m'"WARN $*"$'\e[0m'; }
else
   function echowarn { :; }  ## do nothing
fi

# shellcheck disable=SC2329
if ((${DEBUG:=0}==0)) ;then
   ## runs only if DEBUG enabled
   DEBUG(){ :; }
   echodbg(){ :; }
   catdbg(){ :; }
   teedbg(){ tee; }
   teedbg_surround(){ tee; }
else
   DEBUG(){
      "$@"
      # eval "$@"
   }
   echodbg(){
      echoerr "$@"
   }
   function echodbg { 
      >&2 echo $'\e[0;36m'"${pre:-DBG}  $*"$'\e[0m'
   }
   
   # shellcheck disable=SC2120
   catdbg(){
      prepend | caterr "$@"
   }
   teedbg(){
      tee >(catdbg)
   }
   teedbg_surround(){
      tee >(surround "$1" "$2" | catdbg)
   }
fi

verbal(){
   ## echo command, then execute it
   echoinfo -- "$@"
   "$@"
   # eval "$*"
}

array(){
   array=$1; shift; "$@"
}
contains_element(){
   declare -n __arr=$array
   local elem
   for elem in "${__arr[@]}" ;do [[ "$elem" == "$1" ]] && return 0; done
   return 1
}

kill_sure(){
   ## args: processes PIDs
   ## --- BEHAVIOR ---
   ## 1. send signal TERM
   ## 2. if process still running signal KILL
   ## see also timeout and pv --timer
   kill -TERM "$@" &>/dev/null ||  return 0   ## Already dead
   sleep 0.3
   if kill -0 "$@" &>/dev/null ;then
      echowarn "Force kill $1"
      kill -9 "$@" 2>&-
   fi
}

rotatelog () (
   # local logdir="${logdir:-$mydir}"
   # shellcheck disable=SC2154  ## logdir is to be set externally
   cd "$logdir"
   declare -i rotate_max=${rotate_max:-3}
   expr "${rotate_max:=3}" + 0 &>/dev/null || rotate_max=3
   local n  ##todo local -i
   # shellcheck disable=SC2154,SC2086  ## logdir is to be set externally, no need to "rotate_max", it is number
   echodbg rotatelog in logdir "$logdir" with max $rotate_max
   test -f "log.$rotate_max" && rm -v "log.$rotate_max"  || true
   for lof in $(echo log log.* | tr ' ' '\n' | sort -rV); do
      n=${lof##*.}  ## from aa.bb.c extract c
      expr "${n:=0}" + 0 &>/dev/null || n=0
      ((n>=rotate_max)) && continue
      ((++n))
      test -f $lof || continue
      local f=${lof%.*}   ## from aa.bb.c extract aa.bb
      mv -v "$lof" "$f.$n" >&2 ||true
   done
)

print_stacktrace() {
   set +x
   local -
   local i
   local subshell_str='' && ((BASH_SUBSHELL)) && subshell_str=" subshell=$BASH_SUBSHELL"
   echoerr "Stacktrace:$subshell_str"
   for ((i=${#FUNCNAME[@]}-1; i>${skip_error_handler:-0}; i--)); do
      local func="${FUNCNAME[i]}"
      local file="${BASH_SOURCE[i]}"
      local line="${BASH_LINENO[i-1]}"
      echoerr "  at ${func}() in ${file}:${line}"
   done
}

error_handler() {
   local exit_code=$?
   set +x
   # ((BASH_SUBSHELL!=0)) && return $exit_code
   local cmd="${BASH_COMMAND}"
   local short_cmd="${cmd:0:100}"
   local subshell_str='' && ((BASH_SUBSHELL)) && subshell_str=" subshell=$BASH_SUBSHELL"
   [[ ${#cmd} -gt 100 ]] && short_cmd="${short_cmd::97}..."
   echoerr "Error:$subshell_str command failed with exit_code=$exit_code: $short_cmd"
   skip_error_handler=1 print_stacktrace
   ((BASH_SUBSHELL!=0)) &&
      kill -s SIGHUP $$    # Hangup signal
   # shellcheck disable=SC2086
   exit $exit_code
}

if [[ ${USE_STACKTRACE:=0} != 0 ]]  ;then
   function stacktrace {
      local i=1
      while caller $i | read -r line func file; do
         pre=' in' echodbg "[$i] $file:$line $func()"
         ((i++))
      done
   }
   function stacktrace2 {
      local i=${1:-1} size=${#BASH_SOURCE[@]}
      ((i<size)) && echodbg "STACKTRACE"
      for ((; i < size-1; i++)) ;do  ## -1 to exclude main()
         ((frame=${#BASH_SOURCE[@]}-i-2 ))
         echodbg "[$frame] ${BASH_SOURCE[$i]:-}:${BASH_LINENO[$i]} ${FUNCNAME[$i+1]}()"
      done
   }
else
   function stacktrace { :; }
   function stacktrace2 { :; }
fi

## Do not overwrite but append.
function trap_append {
   local handler="$1"
   shift
   for sigspec in "$@" ;do
      local old_handler
      old_handler="$( trap -p "$sigspec" | 
         perl -e "$/ = undef; <STDIN> =~ /'(.*?)'/s; print \$1;" )"
      handler="$old_handler"$'\n'"$handler"
      # shellcheck disable=SC2064  ## expansion is intended
      trap "$handler" "$sigspec"
   done
}

function OnError {  
   caller | { 
      read -r line file
      echoerr "in $file:$line"
   }  
}
#OnError(){ echoerr "in $BASH_SOURCE:$BASH_LINENO"; stacktrace; }
#OnError(){ echoerr "in ${BASH_SOURCE[1]}:${BASH_LINENO[0]}"; stacktrace; }
trap OnError ERR

trap error_handler ERR
trap error_handler HUP
trap error_handler TERM

## todo function selflog - log stderr and stdout of running script also to file

if [[ -n ${BASH_VERSION-} ]]; then 
    CDA_SRC_ROOT="$(builtin cd -- "$(\dirname -- "$BASH_SOURCE")" && \pwd)"
    CDA_SRC_FILE="$CDA_SRC_ROOT/${BASH_SOURCE##*/}"
elif [[ -n ${ZSH_VERSION-} ]]; then
    CDA_SRC_ROOT="${${(%):-%x}:A:h}"
    CDA_SRC_FILE="${${(%):-%x}:A}"
fi

#------------------------------------------------
# Config Variables
#------------------------------------------------
CDA_DATA_ROOT="${CDA_DATA_ROOT:-$HOME/.cda}"

# load user config
if [[ -f $CDA_DATA_ROOT/config ]]; then
    . "$CDA_DATA_ROOT/config"
fi

CDA_BASH_COMPLETION="${CDA_BASH_COMPLETION:-true}"
CDA_AUTO_ALIAS="${CDA_AUTO_ALIAS:-false}"

if [[ -n ${BASH_VERSION-} ]]; then
    CDA_AUTO_ALIAS_HOOK_TYPE="${CDA_AUTO_ALIAS_HOOK_TYPE:-function}"
elif [[ -n ${ZSH_VERSION-} ]]; then
    CDA_AUTO_ALIAS_HOOK_TYPE="${CDA_AUTO_ALIAS_HOOK_TYPE:-chpwd}"
fi


#------------------------------------------------
# Hook cd for the Auto-Alias feature
#------------------------------------------------
if [[ -n ${TMUX-} || -n ${STY-} ]]; then
    case "$(\tr "[:upper:]" "[:lower:]" <<< "$CDA_AUTO_ALIAS")" in
        0 | true | yes | y | enabled | enable | on)
            case "$CDA_AUTO_ALIAS_HOOK_TYPE" in
                function)
                    cd()
                    {
                        builtin cd "$@"
                        [[ $? -ne 0 ]] && return 1
                        _cda::autoalias::chpwd
                        return 0
                    };;
                prompt)
                    PROMPT_COMMAND=$(\printf -- "%s" "${PROMPT_COMMAND%;}; _cda::autoalias::chpwd;")
                    ;;
                chpwd)
                    if [[ -n ${ZSH_VERSION-} ]]; then
                        \autoload -Uz add-zsh-hook
                        \add-zsh-hook chpwd _cda::autoalias::chpwd
                    else
                        \printf -- "cda: WARNING: CDA_AUTO_ALIAS_HOOK_TYPE=chpwd works only in zsh\n"
                    fi
            esac
            ;;
    esac
fi

#------------------------------------------------
# cda : Main Function
#------------------------------------------------
cda()
{  
    # setup for zsh
    if [[ -n ${ZSH_VERSION-} ]]; then
        \setopt localoptions KSHARRAYS
        \setopt localoptions NO_NOMATCH
        \setopt localoptions SH_WORD_SPLIT
    fi

    #------------------------------------------------
    # Constant variables
    #------------------------------------------------
    # app info
    declare -r APPNAME="cda"
    declare -r VERSION="1.0.0 (2017-02-09)"

    # override system variables
    local IFS=$' \t\n'
    local LC_ALL=C
    local LANG=C

    # save whether the stdin/out/err of the main function is TTY or not.
    [[ -t 0 ]]
    declare -r TTY_STDIN=$?

    [[ -t 1 ]]
    declare -r TTY_STDOUT=$?

    [[ -t 2 ]]
    declare -r TTY_STDERR=$?

    # paths
    declare -r CONFIG_FILE="$CDA_DATA_ROOT/config"
    declare -r LIST_DIR_NAME="lists"
    declare -r LIST_DIR="$CDA_DATA_ROOT/$LIST_DIR_NAME"
    declare -r LIST_DEFAULT_NAME="default"
    declare -r LIST_NAME_FILE="$CDA_DATA_ROOT/listname"
    declare -r AUTO_ALIAS_LIST_NAME=".autolist"
    declare -r AUTO_ALIAS_LIST_FILE="$LIST_DIR/$AUTO_ALIAS_LIST_NAME"
    declare -r AUTO_ALIAS_PWD_FILE="$LIST_DIR/.autopwd"
    
    # flags
    declare -r FLAG_NONE=0
    declare -r FLAG_CD=$((1<<0))
    declare -r FLAG_HELP_SHORT=$((1<<1))
    declare -r FLAG_HELP_FULL=$((1<<2))
    declare -r FLAG_VERSION=$((1<<3))
    declare -r FLAG_ADD=$((1<<4))
    declare -r FLAG_ADD_FORCED=$((1<<5))
    declare -r FLAG_REMOVE=$((1<<6))
    declare -r FLAG_LIST=$((1<<7))
    declare -r FLAG_LIST_FILES=$((1<<8))
    declare -r FLAG_REMOVE_LIST=$((1<<9))
    declare -r FLAG_PATH=$((1<<10))
    declare -r FLAG_USE=$((1<<11))
    declare -r FLAG_USE_TEMP=$((1<<12))
    declare -r FLAG_OPEN=$((1<<13))
    declare -r FLAG_EDIT_LIST=$((1<<14))
    declare -r FLAG_EDIT_CONFIG=$((1<<15))
    declare -r FLAG_SHOW_CONFIG=$((1<<16))
    declare -r FLAG_LIST_NAMES=$((1<<17))
    declare -r FLAG_LIST_PATHS=$((1<<18))
    declare -r FLAG_CHECK=$((1<<19))
    declare -r FLAG_CLEAN=$((1<<20))
    declare -r FLAG_MULTIPLEXER=$((1<<21))
    declare -r FLAG_OVERWRITE=$((1<<22))
    declare -r FLAG_FILTER_FORCED=$((1<<23))
    declare -r FLAG_SUBDIR=$((1<<24))
    declare -r FLAG_UPDATE_AUTOALIAS=$((1<<25))
    declare -r FLAG_BUILTIN_CD=$((1<<26))
    declare -r FLAG_VERBOSE=$((1<<27))
    
    declare -r FLAGS_INCOMPAT=$((
          FLAG_HELP_SHORT | FLAG_HELP_FULL | FLAG_VERSION
        | FLAG_ADD | FLAG_ADD_FORCED | FLAG_REMOVE
        | FLAG_EDIT_LIST | FLAG_EDIT_CONFIG | FLAG_PATH
        | FLAG_LIST_NAMES | FLAG_LIST_PATHS | FLAG_LIST
        | FLAG_LIST_FILES | FLAG_OPEN | FLAG_USE | FLAG_REMOVE_LIST
        | FLAG_CHECK | FLAG_CLEAN | FLAG_SHOW_CONFIG
        | FLAG_UPDATE_AUTOALIAS))

    # config variables
    declare -r CDA_BASH_COMPLETION_DEFAULT=true
    declare -r CDA_CMD_FILTER_DEFAULT="percol:peco:fzf:fzy"
    declare -r CDA_CMD_OPEN_DEFAULT="xdg-open:open:ranger:mc"
    declare -r CDA_CMD_EDITOR_DEFAULT="vim:nano:emacs:vi"
    declare -r CDA_ALIAS_MAX_LEN_DEFAULT=16
    declare -r CDA_COLOR_MODE_DEFAULT=auto
    declare -r CDA_BUILTIN_CD_DEFAULT=false
    declare -r CDA_AUTO_ALIAS_DEFAULT=true
    declare -r CDA_AUTO_ALIAS_HOOK_TYPE_DEFAULT="$([[ -n ${ZSH_VERSION-} ]] && \printf "chpwd" || \printf "function")"
    declare -r CDA_LIST_HIGHLIGHT_COLOR_DEFAULT="0;0;32"

    # misc
    declare -r RTN_COMMAND_NOT_FOUND=127

    # check that $CDA_ALIAS_MAX_LEN is valid
    if ! _cda::num::is_number "${CDA_ALIAS_MAX_LEN-}" || [[ ! $CDA_ALIAS_MAX_LEN -gt 0 ]]; then
        CDA_ALIAS_MAX_LEN=$CDA_ALIAS_MAX_LEN_DEFAULT
    fi


    #------------------------------------------------
    # Setup config directories and files
    #------------------------------------------------
    local USING_LIST_FILE=
    if ! _cda::setup::init; then
        return 1
    fi


    #------------------------------------------------
    # Parse arguments and set flags
    #------------------------------------------------
    local Flags=0 # set according to options
    local Argv    # stores args other than options
    Argv=()

    # variables that store each option arguments
    local Optarg_add=              # -a --add
    local Optarg_add_forced=       # -A --add-forced
    local Optarg_color=            # --color
    local Optarg_cmd_editor=       # -E --cmd-editor
    local Optarg_cmd_filter=       # -F --cmd-filter
    local Optarg_cmd_open=         # -O --cmd-open
    local Optarg_number=           # -n --number
    local Optarg_use_temp=         # -u --use-temp
    local Optarg_use=              # -U --use
   
    # added pipe input as args
    local tmp_argv
    tmp_argv=("$@")
    if [[ ! -t 0 ]]; then
        local arg
        while IFS= \read -r arg || [[ -n $arg ]]
        do
            tmp_argv+=("$arg")
        done < <(\cat -)
    fi

    if ! _cda::option::parse "${tmp_argv[@]-}"; then
        return 1
    fi
    declare -r ARG_C=${#Argv[@]}
    \unset tmp_argv

    
    #------------------------------------------------
    # Check the number of args
    #------------------------------------------------
    local tmp_flags

    # set FLAG_CD
    tmp_flags=$((Flags & ~(FLAG_USE_TEMP | FLAG_FILTER_FORCED | FLAG_MULTIPLEXER | FLAG_SUBDIR | FLAG_BUILTIN_CD | FLAG_VERBOSE)))
    if [[ $tmp_flags -eq $FLAG_NONE ]]; then
        _cda::flag::set $FLAG_CD || return 1
    fi

    # check options requiring 0 or 1 arg
    tmp_flags=$((Flags & (FLAG_ADD | FLAG_ADD_FORCED)))
    if [[ $tmp_flags -ne $FLAG_NONE && $ARG_C -gt 1 ]]; then
        _cda::msg::error ERROR "Too Much Arguments" ""
        return 1
    fi

    # check options requiring NO args
    tmp_flags=$((Flags & (FLAG_VERSION | FLAG_HELP_SHORT | FLAG_HELP_FULL
            | FLAG_LIST_FILES | FLAG_EDIT_LIST | FLAG_SHOW_CONFIG | FLAG_EDIT_CONFIG)))
    if [[ $tmp_flags -ne $FLAG_NONE && $ARG_C -ne 0 ]]; then
        _cda::msg::error WARNING "Unnecessary Arguments Given: " "${Argv[*]}"
    fi
    \unset tmp_flags


    #------------------------------------------------
    # Actions that manage list files
    #------------------------------------------------
    # -U --use : changed the default list file
    if _cda::flag::match $FLAG_USE; then
        _cda::setup::use "$Optarg_use"
        return $?
    fi

    # -u --use-temp : temporarily switch to the specified list
    if _cda::flag::match $FLAG_USE_TEMP; then
        _cda::setup::use --temp "$Optarg_use_temp"
        if [[ $? -ne 0 ]]; then
            return 1
        fi
    fi

    # -m --multiplexer : temporarily switch to the auto-alias list
    if _cda::flag::match $FLAG_MULTIPLEXER; then
        _cda::setup::use --temp "$AUTO_ALIAS_LIST_NAME"
        if [[ $? -ne 0 ]]; then
            return 1
        fi
        _cda::autoalias::clear
    fi

    # -L --list-files
    if _cda::flag::match $FLAG_LIST_FILES; then
        _cda::setup::list_files
        return $?
    fi

    # -R --remove-list
    if _cda::flag::match $FLAG_REMOVE_LIST; then
        _cda::setup::remove_list "$Optarg_remove_list"
        return $?
    fi


    #------------------------------------------------
    # Actions that use aliases
    #------------------------------------------------
    # cd
    if _cda::flag::match $FLAG_CD; then
        _cda::cd::cd "${Argv[@]-}"
        return $?
    fi

    # -p --path
    if _cda::flag::match $FLAG_PATH; then
        local abs_path="$(_cda::list::path "${Argv[@]-}")"
        [[ -z $abs_path ]] && return 1
        \printf -- "%s\n" "$abs_path"
        return $?
    fi

    # -o --open
    if _cda::flag::match $FLAG_OPEN; then
        local abs_path="$(_cda::list::path "${Argv[@]-}")"
        [[ -z $abs_path ]] && return 1
        _cda::cmd::exec OPEN "$abs_path"
        return $?
    fi


    #------------------------------------------------
    # Actions that manage aliases
    #------------------------------------------------
    # -l --list
    if _cda::flag::match $FLAG_LIST; then
        _cda::list::list "${Argv[@]-}"
        return $?
    fi

    # --list-names
    if _cda::flag::match $FLAG_LIST_NAMES; then
        _cda::list::print -n "${Argv[@]-}"
        return $?
    fi

    # --list-paths
    if _cda::flag::match $FLAG_LIST_PATHS; then
        _cda::list::print -p "${Argv[@]-}"
        return $?
    fi

    # -e --edit
    if _cda::flag::match $FLAG_EDIT_LIST; then
        _cda::cmd::exec EDITOR "$USING_LIST_FILE"
        return $?
    fi

    # -a --add
    if _cda::flag::match $FLAG_ADD; then
        _cda::list::add "$Optarg_add" "${Argv[0]-}"
        return $?
    fi

    # -A --add-forced
    if _cda::flag::match $FLAG_ADD_FORCED; then
        _cda::list::add "$Optarg_add_forced" "${Argv[0]-}"
        return $?
    fi

    # -r remove
    if _cda::flag::match $FLAG_REMOVE; then
        _cda::list::remove "${Argv[@]-}"
        return $?
    fi

    # -c, --check
    if _cda::flag::match $FLAG_CHECK; then
        _cda::list::check "${Argv[@]-}"
        return $?
    fi

    # -C | --clean
    if _cda::flag::match $FLAG_CLEAN; then
        _cda::list::clean "${Argv[@]-}"
        return $?
    fi

    # --update-autoalias
    if _cda::flag::match $FLAG_UPDATE_AUTOALIAS; then
        _cda::autoalias::update
        return $?
    fi


    #------------------------------------------------
    # Actions that do not require aliases
    #------------------------------------------------
    # --version
    if _cda::flag::match $FLAG_VERSION; then
        \printf -- "%s\n" "$APPNAME $VERSION"
        return $?
    fi

    # -h --help
    if _cda::flag::match $FLAG_HELP_SHORT; then
        _cda::help::show --short
        return $?
    fi

    # -H --help-full
    if _cda::flag::match $FLAG_HELP_FULL; then
        _cda::help::show
        return $?
    fi

    # --config
    if _cda::flag::match $FLAG_EDIT_CONFIG; then
        _cda::cmd::exec EDITOR "$CONFIG_FILE"
        return $?
    fi

    # --show-config
    if _cda::flag::match $FLAG_SHOW_CONFIG; then
        _cda::config::show
        return $?
    fi

    return 1
}


#------------------------------------------------
# _cda::setup
#------------------------------------------------
_cda::setup::init()
{
    if [[ ! $CDA_DATA_ROOT =~ ^/ ]]; then
        _cda::msg::error FATAL "Invalid CDA_DATA_ROOT: " "$CDA_DATA_ROOT"
        return 1
    fi

    # does the data dir exist?
    if [[ ! -e $CDA_DATA_ROOT ]]; then
        if ! \mkdir -p -- "$CDA_DATA_ROOT"; then
            _cda::msg::error FATAL "Could not create the data dir: " "$CDA_DATA_ROOT"
            return 1
        fi
    fi
    
    # does the list dir exist?
    if [[ ! -e $LIST_DIR ]]; then
        if ! \mkdir -p -- "$LIST_DIR"; then
            _cda::msg::error FATAL "Could not create the list dir: " "$LIST_DIR"
            return 1
        fi
    fi

    # does the default list file exist?
    if [[ ! -e $LIST_DIR/$LIST_DEFAULT_NAME ]]; then
        if ! \touch -- "$LIST_DIR/$LIST_DEFAULT_NAME"; then
            _cda::msg::error FATAL "Could not create the default list file: " "$LIST_DIR/$LIST_DEFAULT_NAME"
            return 1
        fi
    fi

    # does the listname file exist?
    if [[ ! -e $LIST_NAME_FILE || ! -s $LIST_NAME_FILE ]]; then
        if ! _cda::setup::use "$LIST_DEFAULT_NAME"; then
            _cda::msg::error FATAL "Could not create the file: " "$LIST_NAME_FILE"
            return 1
        fi
    fi

    # does the using list file exist?
    local list_name="$(\cat "$LIST_NAME_FILE")"
    USING_LIST_FILE="$LIST_DIR/$list_name"
    if [[ ! -e $USING_LIST_FILE ]]; then
        if ! _cda::setup::use "$list_name"; then
            _cda::msg::error FATAL "Could not create the file: " "$list_name"
            return 1
        fi
    fi

    # is the using list file readable?
    if [[ ! -r $USING_LIST_FILE ]]; then
        _cda::msg::error FATAL "Could not read a file: " "$USING_LIST_FILE"
        return 1
    fi

    # does the config file exist?
    if [[ ! -f $CONFIG_FILE ]]; then
        if ! \touch -- "$CONFIG_FILE"; then
            _cda::msg::error FATAL "Could not create a file: " "$CONFIG_FILE"
            return 1
        fi
        _cda::config::create
    fi

    # is the config file readable?
    if [[ ! -r $CONFIG_FILE ]]; then
        _cda:msg FATAL "Could not read a file: " "$CONFIG_FILE"
        return 1
    fi

    # does the auto-alias list file exist?
    if [[ ! -e $AUTO_ALIAS_LIST_FILE ]]; then
        if ! \touch -- "$AUTO_ALIAS_LIST_FILE"; then
            _cda::msg::error FATAL "Could not create the auto-alias list file: " "$AUTO_ALIAS_LIST_FILE"
            return 1
        fi
    fi

    # does the auto-pwd file exist?
    if [[ ! -e $AUTO_ALIAS_PWD_FILE ]]; then
        if ! \touch -- "$AUTO_ALIAS_PWD_FILE"; then
            _cda::msg::error FATAL "Could not create the auto-pwd file: " "$AUTO_ALIAS_PWD_FILE"
            return 1
        fi
    fi

    return 0
}

# -L --list-files
_cda::setup::list_files()
{
    local curr_name="$(\cat "$LIST_NAME_FILE")"
    local IFS= name star
    while \read -r name || [[ -n $name ]]
    do
        star="  "
        if [[ $name == $curr_name ]]; then
            if _cda::msg::should_color 1; then
                name=$(_cda::text::color -f green -- "$name")
            fi
            star="* "
        fi
        \printf -- "%b\n" "$star$name"
    done < <(\ls -1 -- "$LIST_DIR")
}

# -R --remove-list
_cda::setup::remove_list()
{
    local list_name="$1"
    local curr_name="$(\cat $LIST_NAME_FILE)"

    if [[ ! $list_name =~ ^[a-zA-Z0-9_]+$ ]]; then
        _cda::msg::error ERROR "The list name can not include characters other than \"a-zA-Z0-9_\""
        return 1
    fi

    if [[ ! -e $LIST_DIR/$list_name ]]; then
        _cda::msg::error ERROR "No Such File: " "$LIST_DIR/$list_name"
        return 1
    fi

    if [[ ! -f $LIST_DIR/$list_name ]]; then
        _cda::msg::error ERROR "Not File: " "$LIST_DIR/$list_name"
        return 1
    fi

    if ! rm "$LIST_DIR/$list_name"; then
        _cda::msg::error ERROR "Could Not Remove: " "$LIST_DIR/$list_name"
        return 1
    fi

    if [[ $list_name == $curr_name ]]; then
        _cda::msg::error WARNING "Removed: " "$LIST_DIR/$list_name"
        _cda::msg::error WARNING "The current using list was removed."
        _cda::setup::use "$LIST_DEFAULT_NAME"
    else
        _cda::text::color -f green -n -- "Removed: $LIST_DIR/$list_name"
    fi
}

# -U --use -u --use-temp
_cda::setup::use()
{
    local args temp=false
    args=()
    while [[ $# -ne 0 ]]
    do
        case "$1" in
            -t|--temp) temp=true; \shift;;
            --) \shift; args+=("$@"); \break;;
            *)  args+=("$1"); \shift;;
        esac
    done
    local list_name="${args[0]-}"

    # temporarily change
    if [[ $temp == true ]]; then
        # validate the name of the specified using list 
        if [[ $list_name != $AUTO_ALIAS_LIST_NAME && ! $list_name =~ ^[a-zA-Z0-9_]+$ ]]; then
            _cda::msg::error ERROR "The list name can not include characters other than \"a-zA-Z0-9_\""
            return 1
        fi

        if [[ ! -f $LIST_DIR/$list_name ]]; then
            _cda::msg::error ERROR "No Such List File : " "$LIST_DIR/$list_name"
            return 1
        fi

    # change default list
    else    
        # check using list name
        if [[ ! $list_name =~ ^[a-zA-Z0-9_]+$ ]]; then
            _cda::msg::error ERROR "The list name can not include characters other than \"a-zA-Z0-9_\""
            return 1
        fi

        # does the specified name list exist?
        if [[ ! -f $LIST_DIR/$list_name ]]; then
            # create if not exist
            if ! \touch -- "$LIST_DIR/$list_name"; then
                _cda::msg::error ERROR "Could not create a file: " "$LIST_DIR/$list_name"
                return 1
            fi
            _cda::text::color -f green -n -- "Created: $LIST_DIR/$list_name" | _cda::msg::filter 
        fi

        # Write the using list name to the listname file
        if ! $(printf -- "%s\n" "$list_name" > "$LIST_NAME_FILE"); then
            _cda::msg::error ERROR "Could not write to the file: " "$LIST_DIR_NAME/$list_name"
            return 1
        fi

        _cda::text::color -f green -n -- "Using: $LIST_DIR/$list_name" | _cda::msg::filter
    fi

    USING_LIST_FILE="$LIST_DIR/$list_name"
}


#------------------------------------------------
# _cda::config
#------------------------------------------------
_cda::config::create()
{
<< __EOCFG__ \cat > "$CONFIG_FILE"
# CDA_BASH_COMPLETION=true
# CDA_CMD_FILTER=$CDA_CMD_FILTER_DEFAULT
# CDA_CMD_OPEN=$CDA_CMD_OPEN_DEFAULT
# CDA_CMD_EDITOR=$CDA_CMD_EDITOR_DEFAULT
# CDA_BUILTIN_CD=false
# CDA_AUTO_ALIAS=false
# CDA_AUTO_ALIAS_HOOK_TYPE=$CDA_AUTO_ALIAS_HOOK_TYPE_DEFAULT
# CDA_COLOR_MODE=$CDA_COLOR_MODE_DEFAULT
# CDA_LIST_HIGHLIGHT_COLOR="$CDA_LIST_HIGHLIGHT_COLOR_DEFAULT"
# CDA_ALIAS_MAX_LEN=$CDA_ALIAS_MAX_LEN_DEFAULT
__EOCFG__
}

_cda::config::show()
{
<< __EOCFG__ \cat
CDA_SRC_ROOT="$CDA_SRC_ROOT"
CDA_SRC_FILE="$CDA_SRC_FILE"
CDA_DATA_ROOT="$CDA_DATA_ROOT"
CDA_BASH_COMPLETION=${CDA_BASH_COMPLETION:-CDA_BASH_COMPLETION_DEFAULT}
CDA_CMD_FILTER=${CDA_CMD_FILTER:-$CDA_CMD_FILTER_DEFAULT}
CDA_CMD_OPEN=${CDA_CMD_OPEN:-$CDA_CMD_OPEN_DEFAULT}
CDA_CMD_EDITOR=${CDA_CMD_EDITOR:-$CDA_CMD_EDITOR_DEFAULT}
CDA_BUILTIN_CD=${CDA_BUILTIN_CD:-$CDA_BUILTIN_CD_DEFAULT}
CDA_AUTO_ALIAS=${CDA_AUTO_ALIAS:-$CDA_AUTO_ALIAS_DEFAULT}
CDA_AUTO_ALIAS_HOOK_TYPE=${CDA_AUTO_ALIAS_HOOK_TYPE:-$CDA_AUTO_ALIAS_HOOK_TYPE_DEFAULT}
CDA_COLOR_MODE=${CDA_COLOR_MODE:-$CDA_COLOR_MODE_DEFAULT}
CDA_LIST_HIGHLIGHT_COLOR="${CDA_LIST_HIGHLIGHT_COLOR:-$CDA_LIST_HIGHLIGHT_COLOR_DEFAULT}"
CDA_ALIAS_MAX_LEN=$CDA_ALIAS_MAX_LEN
__EOCFG__
}


#------------------------------------------------
# _cda::flag
#------------------------------------------------
_cda::flag::set()
{
    [[ -z ${1-} ]] && return 1
    if ! _cda::num::is_number $1; then
        return 1
    fi
    Flags=$((Flags | $1))
}

_cda::flag::match()
{
    [[ -z ${1-} ]] && return 1
    _cda::num::andmatch $Flags $1
}


#------------------------------------------------
# _cda::option
#------------------------------------------------
_cda::option::to_flag()
{
    [[ -z ${1-} ]] && return 1

    case $1 in
        -a | --add)             \printf -- $FLAG_ADD;;
        -A | --add-forced)      \printf -- $FLAG_ADD_FORCED;;
        -B | --builtin-cd)      \printf -- $FLAG_BUILTIN_CD;;
        -c | --check)           \printf -- $FLAG_CHECK;;
        -C | --clean)           \printf -- $FLAG_CLEAN;;
        -e | --edit)            \printf -- $FLAG_EDIT_LIST;;
        -f | --filter)          \printf -- $FLAG_FILTER_FORCED;;
        -h | --help)            \printf -- $FLAG_HELP_SHORT;;
        -H | --help-full)       \printf -- $FLAG_HELP_FULL;;
        -l | --list)            \printf -- $FLAG_LIST;;
        -L | --list-files)      \printf -- $FLAG_LIST_FILES;;
        -o | --open)            \printf -- $FLAG_OPEN;;
        -p | --path)            \printf -- $FLAG_PATH;;
        -r | --remove)          \printf -- $FLAG_REMOVE;;
        -R | --remove-list)     \printf -- $FLAG_REMOVE_LIST;;
        -m | --multiplexer)     \printf -- $FLAG_MULTIPLEXER;;
        -s | --subdir)          \printf -- $FLAG_SUBDIR;;
        -u | --use-temp)        \printf -- $FLAG_USE_TEMP;;
        -U | --use)             \printf -- $FLAG_USE;;
        -v | --verbose)         \printf -- $FLAG_VERBOSE;;
        --version)              \printf -- $FLAG_VERSION;;
        --list-names)           \printf -- $FLAG_LIST_NAMES;;
        --list-paths)           \printf -- $FLAG_LIST_PATHS;;
        --config)               \printf -- $FLAG_EDIT_CONFIG;;
        --show-config)          \printf -- $FLAG_SHOW_CONFIG;;
        --update-autoalias)     \printf -- $FLAG_UPDATE_AUTOALIAS;;

        -E | --cmd-editor)      \printf -- $FLAG_NONE;;
        -F | --cmd-filter)      \printf -- $FLAG_NONE;;
        -n | --number)          \printf -- $FLAG_NONE;;
        -O | --cmd-open)        \printf -- $FLAG_NONE;;
        --color)                \printf -- $FLAG_NONE;;

        *)                      \printf -- $FLAG_NONE; return 1;;
    esac
}

_cda::option::set()
{
    [[ -z ${1-} ]] && return 1

    local flag="$(_cda::option::to_flag "$1")"
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    _cda::num::andmatch $Flags $flag && return 0 #already exists
    _cda::num::andmatch $flag $FLAGS_INCOMPAT && Err_incompat+=("$1")
    _cda::flag::set $flag
}

_cda::option::parse()
{
    local rtn=0
    local Err_incompat err_noarg_s err_noarg_l err_undef_s err_undef_l
    Err_incompat=()
    err_noarg_s=()
    err_noarg_l=()
    err_undef_s=()
    err_undef_l=()

    local optname optarg is_split_optarg
    local op detected_opts rest_opts shift_cnt
    while [[ $# -ne 0 ]]
    do
        # get an optname and optarg
        if [[ ${1-} =~ ^--[a-zA-Z0-9_]+(-[a-zA-Z0-9_]+)*=(.+)? ]]; then
            # split a long option into a name and an arg
            is_split_optarg=true
            optname="${1%%=*}"
            optarg="${1#*=}"
        else
            is_split_optarg=false
            optname="${1-}"
            if [[ -n ${2+_} ]]; then
                optarg="$2"
            else
                unset optarg
            fi
        fi

        case "$optname" in
            # options requiring arg
            -a | --add | \
            -A | --add-forced | \
            -E | --cmd-editor | \
            -F | --cmd-filter | \
            -n | --number | \
            -O | --cmd-open | \
            -u | --use-temp | \
            -U | --use | \
            -R | --remove-list | \
            --color \
            )
                if [[ -z ${optarg+_} || ($optarg =~ ^--?.+ && $is_split_optarg == false) ]]; then
                    case $optname in
                        --*)    err_noarg_l+=("$optname");;
                        -*)     err_noarg_s+=("$optname");;
                    esac
                    \shift
                    continue
                fi

                _cda::option::set $optname || return 1
                case $optname in
                    -a | --add)             Optarg_add="$optarg";;
                    -A | --add-forced)      Optarg_add_forced="$optarg";;
                    -E | --cmd-editor)      Optarg_cmd_editor="$optarg";;
                    -F | --cmd-filter)      Optarg_cmd_filter="$optarg";;
                    -n | --number)          Optarg_number="$optarg";;
                    -O | --cmd-open)        Optarg_cmd_open="$optarg";;
                    -R | --remove-list)     Optarg_remove_list="$optarg";;
                    -u | --use-temp)        Optarg_use_temp="$optarg";;
                    -U | --use)             Optarg_use="$optarg";;
                    --color)                Optarg_color="$optarg";;
                esac
                
                if [[ $is_split_optarg == true ]]; then
                    \shift
                else
                    \shift 2
                fi
                ;;

            # options requiring NO arg
            -B | --builtin-cd | \
            -c | --check | \
            -C | --clean | \
            -e | --edit | \
            -f | --filter | \
            -h | --help | \
            -H | --help-full | \
            -l | --list | \
            -L | --list-files | \
            -o | --open | \
            -p | --path | \
            -r | --remove | \
            -m | --multiplexer | \
            -s | --subdir | \
            -v | --verbose | \
            --version | \
            --list-names | \
            --list-paths | \
            --config | --show-config | \
            --update-autoalias \
            )
                _cda::option::set $optname || return 1
                \shift
                ;;
            --)
                \shift
                Argv+=("$@")
                \break
                ;;
            --*)
                err_undef_l+=("$optname")
                \shift
                ;;
            -)
                Argv+=("$optname")
                \shift
                ;;
            -*)
                detected_opts=
                rest_opts=
                shift_cnt=1

                # clustered short options requiring an argument
                for op in a A E F n O R u U
                do
                    [[ ! $optname =~ $op ]] && continue
                    detected_opts="${detected_opts}$op"

                    if [[ -z ${optarg+_} || (! $optname =~ ${op}$ || $optarg =~ ^--?.+) ]]; then
                        err_noarg_s+=("-$op")
                        continue
                    fi
                    _cda::option::set "-$op" || return 1

                    case $op in
                        a)  Optarg_add="$optarg";;
                        A)  Optarg_add_forced="$optarg";;
                        E)  Optarg_cmd_editor="$optarg";;
                        F)  Optarg_cmd_filter="$optarg";;
                        n)  Optarg_number="$optarg";;
                        O)  Optarg_cmd_open="$optarg";;
                        R)  Optarg_remove_list="$optarg";;
                        u)  Optarg_use_temp="$optarg";;
                        U)  Optarg_use="$optarg";;
                    esac
                    shift_cnt=2
                done

                # clustered short options requiring NO argument
                for op in B c C e f h H l L m o p r s v
                do
                    [[ ! $optname =~ ${op} ]] && continue
                    detected_opts="${detected_opts}$op"
                    _cda::option::set "-$op" || return 1
                done

                # undefined short option
                rest_opts="$(
                    \printf -- "%s\n" "-$optname" \
                    | \sed -e "s/[-$detected_opts]//g" \
                           -e 's/\([^ ]\)/ -\1/g')"

                err_undef_s+=($rest_opts)
                \shift $shift_cnt
                ;;
            '')
                # supports a blank arg
                Argv+=("")
                \shift
                ;;
            *)
                Argv+=("$optname") 
                \shift
                ;;
        esac
    done

    local msg

    # check undefined options
    if [[ ${#err_undef_s[@]} -ne 0 || ${#err_undef_l[@]} -ne 0 ]]; then
        msg=$(<<< "${err_undef_s[*]-} ${err_undef_l[*]-}" \tr " " "\n" | \sed '/^$/d' | \sort | \uniq | \tr "\n" " ")
        _cda::msg::error WARNING "Undefined Option(s): " "$msg"
    fi

    # check options requiring arg
    if [[ ${#err_noarg_s[@]} -ne 0 || ${#err_noarg_l[@]} -ne 0 ]]; then
        msg=$(<<< "${err_noarg_s[*]-} ${err_noarg_l[*]-}" \tr " " "\n" | \sed '/^$/d' | \sort | \uniq | \tr "\n" " ")
        _cda::msg::error ERROR "Argument Required: " "$msg"
        rtn=1
    fi

     # check incompatible options
    if [[ ${#Err_incompat[*]} -gt 1 ]]; then
        msg=$(<<< "${Err_incompat[*]}" \tr " " "\n" | \sed '/^$/d' | \sort | \uniq | \tr "\n" " ")
        _cda::msg::error ERROR "Incompatible Options: " "$msg"
        rtn=1
    fi

    return $rtn
}


#------------------------------------------------
# _cda::cd
#------------------------------------------------
_cda::cd::cd()
{
    local abs_path="$(_cda::list::path "${@-}")"
    [[ -z $abs_path ]] && return 1

    if ! _cda::dir::check "$abs_path"; then
        return 1
    fi

    local rtn
    if _cda::flag::match $FLAG_BUILTIN_CD || _cda::utils::is_true "${CDA_BUILTIN_CD-}"; then
        builtin cd "$abs_path"
        rtn=$?

        # instead of the hook function overriding cd command
        if [[ rtn -eq 0 ]] \
        && _cda::utils::is_true "${CDA_AUTO_ALIAS}" \
        && [[ (-n ${TMUX-} || -n ${STY-}) && "$CDA_AUTO_ALIAS_HOOK_TYPE" == "function" ]]; then
            _cda::autoalias::chpwd
        fi
    else
        cd "$abs_path"
        rtn=$?
    fi
    return $rtn
}


#------------------------------------------------
# _cda::alias
#------------------------------------------------
_cda::alias::validate()
{
    local args type= strict= error= show_error=
    args=()
    while [[ $# -ne 0 ]]
    do
        case "$1" in
            -n | --name) type=name; \shift;;
            -l | --line) type=line; \shift;;
            -s | --strict) strict=true; \shift;;
            --show-error) show_error=true; \shift;;
            -)  args+=("$1"); \shift;;
            --) \shift; args+=("$@"); \break;;
            -*) _cda::msg::internal_error "Illegal Option: " "$1"; return 1;;
            *)  args+=("$1"); \shift;;
        esac
    done
    [[ ${#args[@]} -eq 0 || -z $type ]] && return 1

    local arg
    for arg in "${args[@]}"
    do
        case "$type" in
            name)
                if [[ $strict == true ]]; then
                    [[ $arg =~ ^[a-zA-Z0-9_]{1,${CDA_ALIAS_MAX_LEN}}$ ]]
                else
                    [[ $arg =~ ^[a-zA-Z0-9_]{1,}$ ]]
                fi

                if [[ $? -ne 0 ]]; then
                    error=true
                    if [[ $show_error == true ]]; then
                        _cda::msg::error WARNING "Invalid Alias Name: " "$arg"
                    fi
                fi
                ;;
            line)
                if [[ $strict == true ]]; then
                    local name_part="${arg%%/*}"
                    [[ $arg =~ ^[a-zA-Z0-9_]{1,$CDA_ALIAS_MAX_LEN}\ +/.*$ && ${#name_part} -eq $((CDA_ALIAS_MAX_LEN + 1)) ]]
                else
                    [[ $arg =~ ^[a-zA-Z0-9_]+[\ $'\t']+/.*$ ]]
                fi

                if [[ $? -ne 0 ]]; then
                    error=true
                    if [[ $show_error == true ]]; then
                        _cda::msg::error WARNING "Invalid Alias: " "$arg"
                    fi
                fi
                ;;
        esac
    done

    [[ $error != true ]]
    return $?
}

_cda::alias::name()
{
    local line="${1-}"
    if ! _cda::alias::validate --line "$line"; then
        return 1
    fi
    local IFS=$' \t\n'
    \printf -- "%s" ${line%% *}
}

_cda::alias::path()
{
    local line="${1-}"
    if ! _cda::alias::validate --line "$line"; then
        return 1
    fi
    \printf -- "%s" "/${line#*/}"
}

_cda::alias::format()
{
    [[ -z "${1-}" || -z "${2-}" ]] && return 1
    \printf -- "%-${CDA_ALIAS_MAX_LEN}s %s\n" "$1" "$2"
}


#------------------------------------------------
# _cda::list
#------------------------------------------------
_cda::list::print()
{
    local args names_only=false paths_only=false
    args=()
    while [[ $# -ne 0 ]]
    do
        case "$1" in
            -n) names_only=true; \shift;;
            -p) paths_only=true; \shift;;
            -)  args+=("$1"); \shift;;
            --) \shift; args+=("$@"); \break;;
            -*) _cda::msg::internal_error "Illegal Option: " "$1"; return 1;;
            *)  args+=("$1"); \shift;;
        esac
    done

    if [[ -z "${args[@]-}" ]]; then
        if [[ "$names_only" == true ]]; then
            \awk 'NF' "$USING_LIST_FILE" | \awk '{ print $1 }'
            _cda::utils::check_pipes
        elif [[ "$paths_only" == true ]]; then
            \awk 'NF' "$USING_LIST_FILE" \
            | \awk -F '/' '{printf "/";for(i=2;i<NF;i++){printf("%s%s",$i,OFS="/")} print $NF}'
            _cda::utils::check_pipes
        else
            \awk 'NF' "$USING_LIST_FILE"
        fi
    else
        if [[ "$names_only" == true ]]; then
            _cda::list::match -p "${args[@]-}" | \awk '{ print $1 }'
            _cda::utils::check_pipes
        elif [[ "$paths_only" == true ]]; then
            _cda::list::match -p "${args[@]-}" \
            | \awk -F '/' '{printf "/";for(i=2;i<NF;i++){printf("%s%s",$i,OFS="/")} print $NF}'
            _cda::utils::check_pipes
        else
            _cda::list::match -p "${args[@]-}"
        fi
    fi
}

# -l --list
_cda::list::list()
{
    if _cda::msg::should_color 1; then
        _cda::list::print "$@" | _cda::list::highlight
        _cda::utils::check_pipes
    else
        _cda::list::print "$@"
    fi
}

_cda::list::highlight()
{
    local color="${CDA_LIST_HIGHLIGHT_COLOR:-${CDA_LIST_HIGHLIGHT_COLOR_DEFAULT}}"
    \sed 's/^\([a-zA-Z0-9_]\{1,\}\)\([ '$'\t'']\)/'$'\033''\['${color}'m\1'$'\033''\[0m\2/g'
}

_cda::list::match()
{
    local args partial= exact=
    args=()
    while [[ $# -ne 0 ]]
    do
        case "$1" in
            -p) partial=true; \shift;;
            -e) exact=true; \shift;;
            -)  args+=("$1"); \shift;;
            --) \shift; args+=("$@"); \break;;
            -*) _cda::msg::internal_error "Illegal Option: " "$1"; return 1;;
            *)  args+=("$1"); \shift;;
        esac
    done

    if ! _cda::alias::validate --name --show-error "${args[@]-}"; then
        return 1
    fi

    # exact OR match
    if [[ "$exact" == true ]]; then
        local regexp="^($(_cda::text::join ' +|' ${args[@]}) +)"
        _cda::list::print | \tr "\t" " " | \grep -E "$regexp"
        _cda::utils::check_pipes
        return $?

    # partial AND match
    else
        local firstArg="${args[0]}"
        local regexp="^${firstArg}[^ ]* +"
        local lines="$(_cda::list::print | \tr "\t" " " | \grep -E "$regexp")"
        [[ -z "$lines" ]] && return 0

        if [[ ${#args[@]} -eq 1 ]]; then
            printf -- "%b\n" "$lines"
            return 0
        else
            \unset args[0]
            args=("${args[@]}")
            local name
            for name in "${args[@]}"
            do
                regexp="^${firstArg}[^ ]*${name}[^ ]* +"
                lines="$(printf -- "%b" "$lines" | \grep -E "$regexp")"
                [[ -z "$lines" ]] && break
            done 
            [[ -n "$lines" ]] && printf -- "%b\n" "$lines"
        fi
    fi
}

_cda::list::select()
{
    local line=

    # no alias name specified
    if [[ -z ${@-} ]]; then
        line=$(_cda::list::print | _cda::cmd::exec FILTER -p)
        
        if [[ $? -eq $RTN_COMMAND_NOT_FOUND ]]; then
            local cnt="$(_cda::list::print | \grep -c "")"
            _cda::list::list >&2
            return $RTN_COMMAND_NOT_FOUND
        fi
        
        if [[ -z $line ]]; then
            return 1
        fi
    else
       
        if ! _cda::alias::validate --name --show-error "${@-}"; then
            return 1
        fi

        local exact_match_line=
        if [[ $# -eq 1 ]]; then
            exact_match_line=$(_cda::list::match -e "${1-}")
        fi
        local partial_match_lines="$(_cda::list::match -p "${@-}")"
        local partial_match_count="$(\grep -c "" <<< "$partial_match_lines")"
        
        # detect undefined alias
        if [[ -z $partial_match_lines ]]; then
            local IFS=$' '
            _cda::msg::error WARNING "No alias matched with: " "${*-}"
            return 1
        fi

        if [[ ! -z $exact_match_line ]] && ! _cda::flag::match $FLAG_FILTER_FORCED; then
            line="$exact_match_line"
        
        elif [[ $partial_match_count -eq 1 ]] && ! _cda::flag::match $FLAG_FILTER_FORCED; then
            line="$partial_match_lines"
        
        elif [[ $partial_match_count -gt 1 ]] || _cda::flag::match $FLAG_FILTER_FORCED; then
            line=$(_cda::cmd::exec FILTER -p <<< "$partial_match_lines")

            if [[ $? -eq $RTN_COMMAND_NOT_FOUND ]]; then
                _cda::list::list "${@-}" >&2
                return $RTN_COMMAND_NOT_FOUND
            fi
        fi
    fi

    if _cda::flag::match $FLAG_VERBOSE; then
        _cda::list::highlight <<< "$line" | _cda::msg::filter 2 >&2
    fi

    \printf -- "%s" "$line"
}

_cda::list::is_empty()
{
    local IFS=$' '
    \set -- $(\wc -c "$USING_LIST_FILE")
    [[ $1 -le 3 ]]
}

_cda::list::path()
{
    local abs_path=

    # with a dir path
    if [[ ${1-} =~ (/|^[.~]) ]]; then
        abs_path=$(_cda::dir::select "${@-}" "$Optarg_number")
    
    elif ! _cda::list::is_empty; then
        # with the last session path
        if _cda::flag::match $FLAG_MULTIPLEXER && [[ "${1-}" == "-" ]]; then
            abs_path=$(_cda::autoalias::lastpwd)

        # with an alias name
        else
            local line="$(_cda::list::select "$@")"
            abs_path="$(_cda::alias::path "$line")"
        fi

        # -s --subdir
        if [[ -n $abs_path ]] && _cda::flag::match $FLAG_SUBDIR; then
            abs_path=$(_cda::dir::select "$abs_path" "$Optarg_number")
        fi
    else
        _cda::msg::error WARNING "No Alias Added: " "$USING_LIST_FILE"
    fi
    
    [[ -z $abs_path ]] && return 1
    \printf -- "%s" "$abs_path"
}

# -a --add
_cda::list::add()
{
    if [[ ! ($# -eq 1 || $# -eq 2) ]]; then
        _cda::msg::error ERROR "Invalid Argument Count: " "$#"
        return 1
    fi

    # alias name
    local alias_name="${1-}"
    local strict="$(_cda::flag::match $FLAG_MULTIPLEXER || \printf -- "--strict")"
    if ! _cda::alias::validate --name $strict "$alias_name"; then
        _cda::msg::error ERROR "Invalid Alias Name: " "$alias_name"
        return 1
    fi

    # path
    # use the current path if a path not specified
    local rel_path="${2-}"
    if [[ -z $rel_path ]]; then
        rel_path=$(\pwd)
    fi
    local abs_path="$(_cda::path::to_abs "$rel_path")"
    if ! _cda::dir::check "$abs_path"; then
        return 1
    fi

    local output_contents=
    local match_line="$(_cda::list::match -e "$alias_name")"
    local new_line="$(_cda::alias::format "$alias_name" "$abs_path")"

    # not exist yet
    if [[ -z $match_line ]]; then
        output_contents="$new_line\n$(_cda::list::print 2>/dev/null)"

    # already exist
    else
        # check duplicated
        local match_name="$(_cda::alias::name "$match_line")"
        local match_path="$(_cda::alias::path "$match_line")"
        if [[ "$alias_name" == "$match_name" && "$abs_path" == "$match_path" ]]; then
            if ! _cda::flag::match $FLAG_ADD_FORCED; then
                _cda::msg::error WARNING "Duplicated: " "$match_name" "\n$(_cda::list::highlight <<< "$match_line")"
            fi
            return 1
        fi

        # -A --add-forced
        if ! _cda::flag::match $FLAG_ADD_FORCED; then
            _cda::msg::error WARNING "Already Exists: " "$match_name" "\n$(_cda::list::highlight <<< "$match_line")"
            return 1
        fi
        output_contents="$new_line\n$(_cda::list::print | \grep -v -E "^$alias_name +/.*")"
    fi

    if _cda::flag::match $FLAG_VERBOSE; then
        _cda::list::highlight <<< "$new_line" | _cda::msg::filter 2 >&2
    fi

    # output to the list file
    \printf -- "%b\n" "$output_contents" | \awk 'NF' | \sort -u > "$USING_LIST_FILE"
    _cda::utils::check_pipes
}

# -r --remove
_cda::list::remove()
{
    local IFS=$' \n\t'
    local name remove_names abs_path lines line
    remove_names=()

    # with NO arg
    if [[ -z ${@-} ]]; then
        line=$(_cda::list::print | sed 's/^/\*\*\*REMOVE\*\*\*    /' | _cda::cmd::exec FILTER -p)
        
        if [[ $? -eq $RTN_COMMAND_NOT_FOUND ]]; then
            return $RTN_COMMAND_NOT_FOUND
        fi
        
        if [[ -z $line ]]; then
            return 1
        fi
        line=$(<<< "$line" sed 's/^\*\*\*REMOVE\*\*\*    //')
        remove_names+=(${line%% *})
    
    # with args
    else
        for name in "${@-}"
        do
            # with a path
            if [[ $name =~ (/|^[.~]) ]]; then
                abs_path=$(_cda::abs_path::to_abs "$name")
                if [[ -z $abs_path ]]; then
                    continue
                fi

                lines=$(< "$USING_LIST_FILE" \sed 's/$/\/\//'| \grep "$abs_path//")
                if [[ -z $lines ]]; then
                    _cda::msg::error WARNING "No Alias with Such Path: " "$abs_path"
                    continue
                fi

                IFS=$'\n'
                for line in $lines
                do
                    IFS=$' \t\n'
                    remove_names+=(${line%% *})
                done
                continue

            # with a name
            elif ! _cda::alias::validate --name --show-error "$name"; then
                continue
            fi

            if [[ -z "$(_cda::list::match -e "$name")" ]]; then
                _cda::msg::error WARNING "No Such Alias: " "$name"
                continue
            fi
            remove_names+=("$name")
        done
    fi

    if [[ ${#remove_names[@]} -eq 0 ]]; then
        return 1
    fi

    if _cda::flag::match $FLAG_VERBOSE; then
        local match_lines="$(_cda::list::match -e "${remove_names[@]}")"
        <<< "$match_lines" \sed 's/^/'$'\033''\[0;0;31mREMOVED: '$'\033''\[0m/g' |  _cda::msg::filter 2 >&2
    fi

    local regexp="^($(_cda::text::join ' +|' ${remove_names[@]}) +)"
    local output_contents="$(_cda::list::print | \grep -v -E "$regexp" | \awk 'NF')"
    \printf -- "%b\n" "$output_contents" > "$USING_LIST_FILE"
}

# -c --check
_cda::list::check()
{
    local line name abs_path title ok col ok_path= err_path rtn
    local IFS=$'\n'
    while read -r line || [[ -n $line ]]
    do
        name=$(_cda::alias::name "$line")
        abs_path=$(_cda::alias::path "$line")

        [[ -d $abs_path && -r $abs_path && -x $abs_path ]] \
        && _cda::alias::validate --line --strict "$line" \
        && continue

        \set -- $(_cda::dir::split_at_error "$abs_path"; \printf -- "$?\n")
        ok_path=$1
        err_path=$2
        rtn=$3

        title=""
        case $rtn in
            1)  
                title="No Such Path:"
                col="red"
                ;;
            2)      
                title="Access Denied:"
                col="red"
                ;;
            3|4|5)
                title="Not Directory:"
                col="red"
                ;;
            *)
                title="Wrong Format:"
                col="yellow"
                err_path=
                ;;
        esac

        title=$(\printf -- "%-14s %s" "$title")
        name=$(\printf -- "%-${CDA_ALIAS_MAX_LEN}s %s" "$name")
        
        {   _cda::text::color -f $col -- "$title$name$ok_path"
            _cda::text::color -f $col -U -n -- "$err_path"
        } | _cda::msg::filter 2 >&2
    done < <(_cda::list::print "${@-}")
    return 0
}

# -C --clean
_cda::list::clean()
{
    local line name abs_path title col remove_names reformatted_lines
    remove_names=()
    reformatted_lines=()
    local IFS=$'\n'
    while read -r line || [[ -n $line ]]
    do
        IFS=$' \t\n'
        name=$(_cda::alias::name "$line")
        abs_path=$(_cda::alias::path "$line")
        
        if [[ -d $abs_path && -r $abs_path && -x $abs_path ]]; then
            if _cda::alias::validate --line --strict "$line"; then
                continue;
            fi
            title="Format: "
            col="green"
            reformatted_lines+=("$(_cda::alias::format "$name" "$abs_path")")
        else
            title="Remove: "
            col="green"
        fi
        remove_names+=("$name")

        {   _cda::text::color -f $col -- "$title"
            _cda::text::color -f $col -n -- "$(_cda::alias::format "$name" "$abs_path")"
        } | _cda::msg::filter 2 >&2
    done < <(_cda::list::print "${@-}")

    # remove
    [[ ${#remove_names[*]} -eq 0 ]] && return 0
    local regexp="^($(_cda::text::join ' +|' ${remove_names[@]}) +)"
    local contents="$(_cda::list::print | \tr "\t" " ")"
    \grep -v -E "$regexp" <<< "$contents" | \awk 'NF' | \sort -u > "$USING_LIST_FILE"
    local rtn=$?

    [[ ${#reformatted_lines[*]} -eq 0 ]] && return $rtn

    # add re-formatted lines
    IFS=$'\n'
    contents=$(_cda::list::print)
    \printf -- $"%b\n%b\n" "$contents" "${reformatted_lines[*]}" | \awk 'NF' | \sort -u > "$USING_LIST_FILE"
    _cda::utils::check_pipes
}


#------------------------------------------------
# _cda::autoalias
#------------------------------------------------

# chpwd is called directly from cd hooked
_cda::autoalias::chpwd()  
{
    [[ -z ${TMUX-} && -z ${STY-} ]] && return 0
    [[ "$PWD" == "$OLDPWD" ]] && return 0
    cda -s --update-autoalias
    return 0
}

# --update-autoalias
_cda::autoalias::update()
{
    [[ -z ${TMUX-} && -z ${STY-} ]] && return 1

    local IFS=$' \t\n' line session hostname winpane alias_name

    # tmux
    if [[ -n ${TMUX-} ]]; then
        line="$(\tmux display -p "#S:#I_#P")"
        session="${line%%:*}"
        winpane="${line#*:}"
        if ! _cda::alias::validate --name "$session"; then
            session=$(\sed -e 's/[^a-zA-Z0-9_]/_/g' <<< "$session")
        fi
        alias_name="${session}_${winpane}"

    # GNU screen
    elif [[ -n ${STY-} ]]; then
        session="${STY#*.}"
        hostname="$(\hostname)"
        hostname="${hostname%%.*}"
        if [[ $session =~ ^[a-z]+-?[0-9]+\.$hostname$ ]]; then
            session="$(\sed -e 's/^[^0-9]\{1,\}-\{0,1\}\([0-9]\{1,\}\)\..*$/\1/' <<< "$session")"
            session=$(\printf -- "%d" $((10#${session})))
        else
            if ! _cda::alias::validate --name "$session"; then
                session=$(\sed -e 's/[^a-zA-Z0-9_]/_/g' <<< "$session")
            fi
        fi
        alias_name="${session}_${WINDOW}"
    fi
    _cda::flag::set $FLAG_ADD_FORCED
    _cda::list::add "$alias_name" "$(\pwd)"
    \pwd > "$AUTO_ALIAS_PWD_FILE"
}

_cda::autoalias::clear()
{
    local IFS=$'\n'
    local names line session hostname alias_name
    names=()

    # tmux
    if _cda::cmd::exist tmux; then
        while IFS= \read -r line || [[ -n "$line" ]]
        do
            session="${line%%:*}"
            if ! _cda::alias::validate --name "$session"; then
                session=$(\sed -e 's/[^a-zA-Z0-9_]/_/g' <<< "$session")
            fi
            alias_name="${session}_[0-9]+_[0-9]+"
            names+=("$alias_name")
        done < <(\tmux ls 2>/dev/null | \grep -E -- '^[^:]+:[ '$'\t'']+[0-9]+[ '$'\t'']+')
    fi

    # GNU screen
    if _cda::cmd::exist screen; then
        hostname="$(\hostname)"
        hostname="${hostname%%.*}"     
        while IFS= \read -r line || [[ -n $line ]]
        do
            line=$(_cda::text::trim "$line")
            session="${line#*.}"
            if [[ $session =~ ^[a-z]+-?[0-9]+\.$hostname$ ]]; then
                session=$(\sed -e 's/^[^0-9]\{1,\}-\{0,1\}\([0-9]\{1,\}\)\..*$/\1/' <<< "$session")
                session=$(\printf -- "%d" $((10#${session})))
            else
                if ! _cda::alias::validate --name "$session"; then
                    session=$(\sed -e 's/[^a-zA-Z0-9_]/_/g' <<< "$session")
                fi
            fi
            alias_name="${session}_[0-9]+"
            names+=("$alias_name")
        done < <(\screen -ls 2>/dev/null | \grep -E -- '^[ '$'\t'']+[0-9]+\.' | \sed -e 's/(.*)$//')
    fi
    if [[ ${#names[*]} -eq 0 ]]; then
        [[ -s $USING_LIST_FILE ]] && : > "$USING_LIST_FILE"
        return $?
    fi
    
    local regexp="^($(_cda::text::join ' +|' ${names[@]}) +)"
    local contents="$(_cda::list::print | \tr "\t" " ")"
    \grep -E "$regexp" <<< "$contents" | \awk 'NF' | \sort -u > "$USING_LIST_FILE"
    _cda::utils::check_pipes
}

_cda::autoalias::lastpwd()
{
    \cat 2>/dev/null -- "$AUTO_ALIAS_PWD_FILE"
}


#------------------------------------------------
# _cda::utils
#------------------------------------------------
_cda::utils::check_pipes()
{
    [[ $(_cda::num::sum ${PIPESTATUS[@]-}) -eq 0 ]]
}

_cda::utils::is_true()
{
    case "$(_cda::text::lower "${1-}")" in
        0 | true | yes | y | enabled | enable | on)     return 0;;
        1 | false | no | n | disabled | disable | off)  return 1;;
        *)                                              return 2;;
    esac
}


#------------------------------------------------
# _cda::num
#------------------------------------------------
_cda::num::is_number()
{
    [[ $# -ne 1 ]] && return 1
    [[ "$1" =~ ^[+-]?[0-9]*[\.]?[0-9]+$ ]]
}

_cda::num::andmatch()
{
    [[ -z ${1-} || -z ${2-} ]] && return 1
    _cda::num::is_number $1 && \
    _cda::num::is_number $2 && \
    [[ $(($1 & $2)) -ne 0 ]]
}

_cda::num::sum()
{
    \awk '{for(i=1; i<=NF; i++){t+=$i}} END{print t}' <<< ${@-}
}


#------------------------------------------------
# _cda::path
#------------------------------------------------
_cda::path::to_abs()
{
    [[ -z ${1-} ]] && return 1

    local abs_path="/" rel_path
    [[ "$1" =~ ^/ ]] && rel_path="$1" || rel_path="$PWD/$1"

    local IFS="/" comp
    for comp in $rel_path
    do
        case "$comp" in
            '.' | '') continue;;
            '..')     abs_path=$(\dirname -- "$abs_path");;
            *)        [[ $abs_path == / ]] && abs_path="/$comp" || abs_path="$abs_path/$comp";;
        esac
    done
    \printf -- "%s" "$abs_path"
}


#------------------------------------------------
# _cda::dir
#------------------------------------------------
_cda::dir::check()
{
    if [[ -d ${1-} && -r ${1-} && -x ${1-} ]]; then
        return 0
    fi

    # split dir path components at error
    local IFS=$'\n'
    local components ok_path err_path rtn
    \set -- $(_cda::dir::split_at_error "$1"; \printf -- "$?\n")
    ok_path=$1
    err_path=$2
    rtn=$3

    # rich message
    case $rtn in
        1)      ok_path=$(_cda::text::color -f red -- "$ok_path")
                err_path=$(_cda::text::color -f red -U -- "$err_path")
                _cda::msg::error ERROR "No Such Path: " "" "$ok_path$err_path";;
                
        2)      ok_path=$(_cda::text::color -f magenta -- "$ok_path")
                err_path=$(_cda::text::color -f magenta -U -- "$err_path")
                _cda::msg::error ERROR "Permission Denied: " "" "$ok_path$err_path";;
                
        3|4|5)  ok_path=$(_cda::text::color -f red -- "$ok_path")
                err_path=$(_cda::text::color -f red -U -- "$err_path")
                _cda::msg::error ERROR "Not Directory: " "" "$ok_path$err_path";;
    esac
    return 1
}

# split dir path components at error
_cda::dir::split_at_error()
{
    declare -r rtn_no_problem=0
    declare -r rtn_not_exist=1
    declare -r rtn_permission_denied=2
    declare -r rtn_regular_file=3
    declare -r rtn_other_files=4
    declare -r rtn_not_path=5

    local abs_path="$(_cda::path::to_abs "$1")"
    if [[ -z $abs_path ]]; then
        \printf -- "\n\n"
        return $rtn_not_path
    fi

    local comp curr_path ok_path= err_path=
    local rtn=$rtn_no_problem
    local IFS=/
    \set -- $abs_path
    for comp in "$@"
    do
        curr_path="${ok_path%/}/$comp"
        if [[ ! -e $curr_path ]]; then
            rtn=$rtn_not_exist
        elif [[ -d $curr_path && (! -r $curr_path || ! -x $curr_path) ]]; then
            rtn=$rtn_permission_denied
        elif [[ -d $curr_path ]]; then
            ok_path="$curr_path"
            \shift
        elif [[ -f $curr_path ]]; then
            rtn=$rtn_regular_file
        else
            rtn=$rtn_other_files
        fi

        if [[ $rtn -ne 0 ]]; then
            err_path="$(_cda::text::join "/" "$@")"
            \break
        fi
    done
    [[ $ok_path != / && ! -z $err_path ]] && ok_path="$ok_path/"
    \printf -- "%b" "$ok_path\n$err_path\n"
    return $rtn
}

_cda::dir::subdirs()
{
    local arg argpath fullpath= alldirs= nolink= parentdir=
    for arg in "$@"
    do
        case "$arg" in
            -f) fullpath=true; \shift;;
            -a) alldirs=a ; \shift;;
            -L) nolink=true; \shift;;
            -p) parentdir=true; \shift;;
            --) \shift; argpath="$@"; \break;;
            *)  argpath="$1"; \shift;;
        esac
    done
    
    local item pdir= dir="$(_cda::path::to_abs "${argpath:-$(\pwd)}")"
    [[ $fullpath == true ]] && pdir="$dir/"
    if [[ $parentdir == true ]]; then
        \printf -- "%s\n" "$pdir."
    fi
    while IFS= \read -r item || [[ -n $item ]]
    do
        [[ ! -d "$dir/$item" || $item =~ ^\.\.?$ ]] && continue
        [[ $nolink == true && -L "$dir/$item" ]] && continue
        \printf -- "%s\n" "$pdir$item"
    done < <(\ls -1$alldirs -- "$dir")
}

_cda::dir::select()
{
    if ! _cda::dir::check "${1-}"; then
        return 1
    fi

    local abs_path="$(_cda::path::to_abs "$1")"
    local new_abs_path= line=
    
    if _cda::num::is_number "${2-}"; then
        local dirnum="$(printf -- "%d" $((10#${2})))"
        if [[ $dirnum -eq 0 ]]; then
            new_abs_path=$abs_path
        else
            line="$(_cda::dir::subdirs -a "$abs_path" | awk "NR==$dirnum")"
            if [[ -z $line ]]; then
                _cda::msg::error WARNING "No Such Subdir Number: " "$2"
                return 1
            fi
            new_abs_path="${abs_path%/}/$(\printf -- "%s\n" "$line")"
        fi

        if _cda::flag::match $FLAG_VERBOSE; then
            printf -- "%-${CDA_ALIAS_MAX_LEN}s %s\n" "$dirnum" "$new_abs_path" | _cda::list::highlight | _cda::msg::filter 2 >&2
        fi
    else
        # count the number of lines to determine padding width
        local dircnt="$(_cda::dir::subdirs -a -p "$abs_path" | \grep -c "")"
        local pad_width="$(($(\wc -c <<< "$dircnt") - 1))"

        if [[ -z "$(_cda::cmd::get filter)" ]]; then
            if _cda::msg::should_color 2; then
                _cda::dir::subdirs -a -p "$abs_path" | \nl -n rz -w $pad_width -v 0 |  _cda::list::highlight >&2
            else
                _cda::dir::subdirs -a -p "$abs_path" | \nl -n rz -w $pad_width -v 0
            fi
            return 1
        fi
        
        # add line numbers and send to a filter
        line="$(_cda::dir::subdirs -a -p "$abs_path" | \nl -n rz -w $pad_width -v 0 | sed 's/^/#/' |  _cda::cmd::exec FILTER -p)"
        [[ -z $line ]] && return 1

        # build a new path
        new_abs_path="${abs_path%/}/$(\printf -- "%s\n" "$line" | \sed -e 's/^#[0-9]\{1,\}'$'\t''//')"

        if _cda::flag::match $FLAG_VERBOSE; then
            local num="$(<<< "$line" sed 's/^#\([0-9]\{1,\}\).*/\1/')"
            printf -- "%-${CDA_ALIAS_MAX_LEN}s %s\n" "$num" "$new_abs_path" | _cda::list::highlight | _cda::msg::filter 2 >&2
        fi
    fi

    if ! _cda::dir::check "$new_abs_path"; then
        return 1
    fi
    \printf -- "%s" "$new_abs_path"
}


#------------------------------------------------
# _cda::text
#------------------------------------------------

# Usage: _cda::text::color [OPTIONS] -- {TEXT}
# e.g.)  _cda::text::color -f red -b green --bold -- "text"
_cda::text::color()
{
    local IFS=$' \t\n'
    declare -r esc_start="\033["
    declare -r esc_end="\033[m"

    # attributes
    declare -r none=0                #
    declare -r bold=1                # -B, --bold
    declare -r lowintensity=2        # -L, --lowintensity
    declare -r italic=3              # -I, --italic
    declare -r underline=4           # -U, --underline
    declare -r blink=5               # -K, --blink
    declare -r fastblink=6           # --KK
    declare -r reverse=7             # -R, --reverse
    declare -r invisible=8           # -V, --invisible
    declare -r strike=9              # -S, --strike
    declare -r dblunderline=21       # --U

    declare -r highintensity=90      # -H
    local newline=                   # -n, --newline

    # color names
    declare -r black=30
    declare -r red=31
    declare -r green=32
    declare -r yellow=33
    declare -r blue=34
    declare -r magenta=35
    declare -r cyan=36
    declare -r white=37
    declare -r default=39

    # fg color + tobg -> bg color
    declare -r tobg=10
    local bg=$((default + tobg))
    local bg_default=$bg
    local fg=$default
    local att=$none

    local args
    args=()
    while [[ $# -ne 0 ]]
    do
        case "$1" in
            -B | --bold)            att=$bold; \shift;;
            -L | --lowintensity)    att=$lowintensity; \shift;;
            -I | --italic)          att=$italic; \shift;;
            -U | --underline)       att=$underline; \shift;;
            -K | --blink)           att=$blink; \shift;;
            --fast-blink)           att=$fastblink; \shift;;
            -R | --reverse)         att=$reverse; \shift;;
            -V | --invisible)       att=$invisible; \shift;;
            -S | --strike)          att=$strike; \shift;;
            --U)                    att=$dblunderline; \shift;;
            -H)                     att=$highintensity; \shift;;
            -n | --newline)         newline="\n"; \shift;;
            -b | -f)
                if [[ -z ${2+_} || ${2-} =~ ^-+ ]]; then
                    \shift
                    continue
                fi

                case $1 in
                    -b)
                        case $2 in
                            black | red | green | yellow | blue | \
                            magenta | cyan | white | default)
                                \eval bg="\$$2"
                                bg=$((bg + tobg))
                                ;;
                        esac
                        ;;
                    -f)
                        case $2 in
                            black | red | green | yellow | blue | \
                            magenta | cyan | white | default)
                                \eval fg="\$$2"
                                ;;
                        esac
                        ;;
                esac
                \shift 2
                ;;
            -)  args+=("$1"); \shift;;
            --) \shift; args+=("$@"); \break;;
            -*) _cda::msg::internal_error "Illegal Option: " "$1"; return 1;;
            *)  args+=("$1");;
        esac
    done


    if [[ $att -eq $none && $bg -ne $bg_default ]]; then
        att=$highintensity
    fi

    local text
    if [[ ${#args[*]} -eq 0 ]]; then
        text=$(\cat -- -)
    else
        text="${args[*]}"
    fi
    \printf -- "%b" "${esc_start}${bg};${att};${fg}m${text}${esc_end}${newline}"
}

_cda::text::strip()
{
    if [[ $# -eq 0 ]]; then
        \sed 's/'$'\033''\[[0-9;]*[JKmsu]//g'
    else
        \sed 's/'$'\033''\[[0-9;]*[JKmsu]//g' <<< "$*"
    fi
}

_cda::text::lower()
{
    if [[ $# -eq 0 ]]; then
        \tr "[:upper:]" "[:lower:]"
    else
        \tr "[:upper:]" "[:lower:]" <<< "$*"
    fi
}

_cda::text::join()
{
    local IFS=
    local delimiter="${1-}"
    \shift
    \printf -- "%s" "${1-}"
    \shift
    \printf -- "%s" "${@/#/$delimiter}"
}

_cda::text::trim()
{
    local var
    if [[ $# -eq 0 ]]; then
        var=$(\cat)
    else
        var="${1-}"
    fi 
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    \printf -- "%s" "$var"
}


#------------------------------------------------
# _cda::msg
#------------------------------------------------
_cda::msg::should_color()
{
    local fd="${1-}"
    case "$(_cda::text::lower "${Optarg_color:-${CDA_COLOR_MODE:-$CDA_COLOR_MODE_DEFAULT}}")" in
        always)   return 0;;
        never)    return 1;;
        auto)     
            case "$fd" in
                1) return $TTY_STDOUT;;
                2) return $TTY_STDERR;;
                *) return 1;;
            esac
            ;;
        *) return 1;;
    esac
}

# escape sequence filter
_cda::msg::filter()
{
    local fd="${1:-1}"
    if _cda::msg::should_color $fd; then
        \cat -- -
    else
        _cda::text::strip
    fi
}

# formatted error message
_cda::msg::error()
{
    local title="${1-}"
    local text="${2-}"
    local value="${3-}"

    local extra=
    if [[ $# -gt 3 ]]; then
        \shift 3
        local IFS=
        extra="$*"
        IFS=$' \t\n'
    fi  

    local col=
    case "$(_cda::text::lower "$title")" in
        notice)             col="-f green";;
        warning|warn)       col="-f yellow";;
        error)              col="-f red";;
        "internal error")   col="-f yellow -b red";;
        fatal)              col="-f white -b red";;
        *)                  col="-f default";;
    esac

    {   _cda::text::color -f $col -- "$title:"
        _cda::text::color -f default -- " $text"
        _cda::text::color $col -- "$value"
        \printf -- "%b\n" "$extra"
    } | _cda::msg::filter 2 >&2
}

_cda::msg::internal_error()
{
    local text="${1-}" value="${2-}" funcs
    funcs=()
    if [[ -n $BASH_VERSION ]]; then
        funcs=("${FUNCNAME[@]}")
    elif [[ -n ZSH_VERSION ]]; then
        funcs=("${funcstack[@]}")
    fi
    _cda::msg::error "INTERNAL ERROR" "${funcs[1]}(): $text" "$value"
    funcs[0]= 
    local IFS=$'\n'
    printf -- "Stack Trace%b\n" "${funcs[*]}"
}


#------------------------------------------------
# _cda::cmd
#------------------------------------------------
_cda::cmd::first_token()
{
    \eval \set -- "${@-}"
    \printf -- "%b" "${1-}"
}

_cda::cmd::exist()
{
    \type "${1-}" >/dev/null 2>&1
}

_cda::cmd::available()
{
    [[ -z ${1-} ]] && return 1
    local IFS=$':'
    \set -- $*
    local cmdline
    for cmdline in "$@"
    do
        if ! _cda::cmd::exist "$(_cda::cmd::first_token "$cmdline")"; then
            continue
        fi
        \printf -- "%b" "$cmdline"
        return 0
    done
    return 1
}

_cda::cmd::get()
{
    local cmd=
    case "$(_cda::text::lower "${1-}")" in
        filter) cmd=$(_cda::cmd::available "${Optarg_cmd_filter:-${CDA_CMD_FILTER:-$CDA_CMD_FILTER_DEFAULT}}");;
        editor) cmd=$(_cda::cmd::available "${Optarg_cmd_editor:-${CDA_CMD_EDITOR:-$CDA_CMD_EDITOR_DEFAULT}}");;
        open)   cmd=$(_cda::cmd::available "${Optarg_cmd_open:-${CDA_CMD_OPEN:-$CDA_CMD_OPEN_DEFAULT}}");;
        *) return 1;;
    esac
    [[ -z $cmd ]] && return 1
    printf -- "%b" "$cmd"
}

_cda::cmd::exec()
{
    local cmd="$(_cda::cmd::get "${1-}")"
    [[ -z $cmd ]] && return $RTN_COMMAND_NOT_FOUND
    \shift
    local args pipe=false
    args=()
    while [[ $# -ne 0 ]]
    do
        case "$1" in
            -p|--pipe) pipe=true; \shift;;
            -)  args+=("$1"); \shift;;
            --) \shift; args+=("$@"); \break;;
            -*) _cda::msg::internal_error "Illegal Option: " "$1"; return 1;;
            *)  args+=("$1"); \shift;;
        esac
    done

    if [[ $pipe == true ]]; then
        \eval "$cmd" < /dev/stdin
    else
        \eval "$cmd" '"${args[@]}"'
    fi
}


#------------------------------------------------
# _cda::help
#------------------------------------------------
# -h --help -H --help-full
_cda::help::show()
{
    local args short=false
    args=()
    while [[ $# -ne 0 ]]
    do
        case "$1" in
            -s|--short) short=true; \shift;;
            -)  args+=("$1"); \shift;;
            --) \shift; args+=("$@"); \break;;
            -*) _cda::msg::internal_error "Illegal Option: " "$1"; return 1;;
            *)  args+=("$1"); \shift;;
        esac
    done

    # Short Help
    if [[ $short == true ]]; then

<< __EOHELP__ \cat | _cda::msg::filter
DESCRIPTION
    cda -- cd with an alias name

OPTIONS
    -a {ALIAS_NAME} [PATH]    Add an alias.
    -r {ALIAS_NAME}           Remove an alias.
    -l                        List aliases.

EXAMPLES
    \$ cda -a foo /baz/bar/foo
    \$ cda foo
    \$ pwd
    /baz/bar/foo

$(_cda::text::color -f green -- "-H, --help-full shows full help.")
__EOHELP__

    # Full Help
    else

<< __EOHELP__ \cat | _cda::msg::filter | \less
------------------------------------------------------------------------
Name        : $APPNAME -- cd with an alias name
Version     : $VERSION
License     : MIT License
Author      : itmst71@gmail.com
URL         : https://github.com/itmst71/cda
Required    : Bash 3.2+ / Zsh 5.1+, Some POSIX commands
Optional    : Interactive Filter(percol, peco, fzf, fzy etc...)
            : Bash-completion
            : Terminal Multiplexer(tmux or GNU screen)
Description : Executes cd with an alias name.
              Supports interactive filters and bash-completion.
------------------------------------------------------------------------

SYNOPSIS
    cda [OPTIONS] [ALIAS_NAME | DIRECTORY_PATH]
            
        \$ cda alias_name

    * The options will work regardless of location.

    * cda supports pipe input.
      But note that cd via a pipe works only in Zsh.
      The features other than cd work in Bash even though via a pipe.

        \$ echo alias_name | cda # works in Zsh only

ALIAS NAME
    An alias name can include only "a-zA-Z0-9_".
    The default max length is 16.
    e.g.) foo, boo_bar, baz001, a, A, 0, _

OPTIONS
    --version
        Show version.

    -h | --help
        Show simple help.
            
    -H | --help-full
        Show full help with less.

    -a | --add {ALIAS_NAME} [PATH]
        Add an alias with a path. If the path is not given,
        the current path is used instead.
    
    -A | -add-forced {ALIAS_NAME} [PATH]
        -a | --add with the flags ignoring duplicated / already-exist
        warnings.

    -r | --remove {ALIAS_NAME [ALIAS_NAME ...]}
        Remove exact matched aliases

    -l | --list [ALIAS_NAME [ALIAS_NAME ...]]
        Show all aliases in the current list.
        Args act as forward match keywords.

    -f | --filter
        Use a filter command to select from all candidate aliases
        even if there is an exact match alias.

    -o | --open [ALIAS_NAME]
        Open an alias path with a file manager.

    -p | --path [ALIAS_NAME]
        Print the path of specified alaias name.

    -e | --edit
        Edit alias list with a text editor.

    -U | --use {LIST_NAME}
        Change the list to use in default.
        If the list specified does not exist, it is created.

    -u | --use-temp {LIST_NAME}
        Change the list to use temporarily.
        Specify one of the list names -L shows.

    -L | --list-files
        Show all list files being in the list directory
        "~/.cda/lists".

    -R | --remove-list {LIST_NAME}
        Remove a list file being in the list directory
        "~/.cda/lists".

    -c | --check [ALIAS_NAME [ALIAS_NAME ...]]
        Check the existence of alias path.

    -C | --clean [ALIAS_NAME [ALIAS_NAME ...]]
        Check the existence of alias paths and remove them
        that do not exist. Also re-format wrong format lines.

    -m | --multiplexer
        Temporarily switch to auto alias list for terminal
        multiplexer.

    -s | --subdir
        Select a subdirectory in the alias path with a filter.
    
    -n | --number {SUBDIR_NUMBER}
        Select a subdirectory by number in the subdirectory mode
        non-interactively.

    -F | --cmd-filter {FILTER_COMMAND}
        Use a specified interactive filter.
        This can override \$CDA_CMD_FILTER variable.

    -O | --cmd-open {OPEN_COMMAND}
        Use a specified command to open a directory path.
        This can override \$CDA_CMD_OPEN variable.

    -E | --cmd-editor {EDITOR_COMMAND}
        Use a specified editor.
        This can override \$CDA_CMD_EDITOR variable.

    -v | --verbose
        Set verbose flag to show more detailed messages.

    --list-names [ALIAS_NAME [ALIAS_NAME ...]]
        List alias names.

    --list-paths [ALIAS_NAME [ALIAS_NAME ...]]
        List alias paths.

    --config
        Open the config file with a text editor.

    --show-config
        Show the config file.

    --color {[auto | always | never]}
        Control error messages to be colored for pipes.

CONFIG VARIABLES
    1. Config variables can be defined in the file below.
       The path can be changed with CDA_DATA_ROOT.

        ~/.cda/config

    2. --config can edit the file quickly.

        \$ cda --config

    4. You can specify multiple commands candidates with
       separating with ":". The first available command is used.
        
        VAR_NAME=cmd1:cmd2:cmd3

    5. If you want to sepecify in a full-path including spaces
       or use with options, write with '"..."' like below.
        
        VAR_NAME=cmd1:'"/the path/to/cmd" -a --long="a b"':cmd3

    6. Set one of the values below to a boolean-like variable.
       Truthy : [ 0, true, yes, y, enabled, enable, on ]
       Falsy  : [ 1, false, no, n, disabled, disable, off ]
       They are NOT case sensitive.

        BOOL_VAR=true

    [ CDA_DATA_ROOT ]  
        Specify the path to the user data directory.
        ***It must be set before "source cda.sh".***
        So it should be written in "~/.bashrc" instead of the config file.

            CDA_DATA_ROOT=\$HOME/.cda

    [ CDA_BASH_COMPLETION ]  
        Set to false if you don't want to use Bash-Completion.
        The defalt is true.

            CDA_BASH_COMPLETION=true

    [ CDA_CMD_FILTER ]
        Specify the name or path of interactive filter commands
        to select an alias from list when no argument is given
        or multiple aliases are hit.
        -F | --cmd-filter can override this.
            
            CDA_CMD_FILTER=$CDA_CMD_FILTER_DEFAULT

    [ CDA_CMD_OPEN ]
        Specify the name or path of file manager commands to open
        the path when using -o | --open.
        -O | --cmd-open can override this.

            CDA_CMD_OPEN=$CDA_CMD_OPEN_DEFAULT
            
    [ CDA_CMD_EDITOR ]
        Specify a name or path of editor commands to edit the list file
        with -e | --edit or the config file with --config.
        -E | --cmd-editor override this.

            CDA_CMD_EDITOR=$CDA_CMD_EDITOR_DEFAULT

    [ CDA_BUILTIN_CD ]
        Set to true if you do not want to be affected by external
        cd extension tools. Default is false.
        -B | --builtin-cd override this and temporarily set to true.

            CDA_BUILTIN_CD=false

    [ CDA_AUTO_ALIAS ]
        Set to false if you don't want to use the auto-alias in terminal
        multiplexer feature. The defalt is true.

            CDA_AUTO_ALIAS=true

    [ CDA_AUTO_ALIAS_HOOK_TYPE ]
        Specify one of [function prompt chpwd] as the hook type of
        cd for the auto-alias in terminal multiplexer feature.
        Only Zsh can use chpwd.

            CDA_AUTO_ALIAS_HOOK_TYPE=function     # Bash
            CDA_AUTO_ALIAS_HOOK_TYPE=chpwd        # Zsh

    [ CDA_COLOR_MODE ]
        Specify one of [never always auto] as the color mode 
        of the output message. When auto is selected, it will automatically
        switch whether or not to color the message depending on whether
        the output destination is a TTY or not.

            CDA_COLOR_MODE=$CDA_COLOR_MODE_DEFAULT

    [ CDA_LIST_HIGHLIGHT_COLOR ]
        Specify the value part of the ANSI escape sequence color codes.
        For example, in case of color codes "\033[0;0;32m",
        specify only "0;0;32".

            CDA_LIST_HIGHLIGHT_COLOR="$CDA_LIST_HIGHLIGHT_COLOR_DEFAULT"

    [ CDA_ALIAS_MAX_LEN ]
        Specify the maximum number of characters for the alias name.
        The default value is 16. After changing the list data can
        be reformatted by executing --clean.

            CDA_ALIAS_MAX_LEN=$CDA_ALIAS_MAX_LEN_DEFAULT
            
__EOHELP__
    fi
    _cda::utils::check_pipes
}


#------------------------------------------------
# Bash-Completion
#------------------------------------------------
if _cda::utils::is_true "$CDA_BASH_COMPLETION"; then

    _cda()
    {
        # for zsh
        if [[ -n ${ZSH_VERSION-} ]] ; then
            \setopt localoptions KSHARRAYS
            \setopt localoptions NO_NOMATCH
            \setopt localoptions SH_WORD_SPLIT
            \setopt localoptions AUTO_PARAM_SLASH
            \setopt localoptions LIST_TYPES
        fi
        
        COMPREPLY=()
        local curr="${COMP_WORDS[COMP_CWORD]}"
        local prev="${COMP_WORDS[COMP_CWORD-1]}"

        local arg optEnd=false idx=0
        for arg in "${COMP_WORDS[@]}"
        do
            [[ $idx -eq $COMP_CWORD ]] && break
            if [[ $arg == -- ]] ; then
                optEnd=true
                \break
            fi
            : $((idx++))
        done

        if [[ $optEnd == false ]] ; then
            case "$prev" in
                # options requiring no more argument
                -e | --edit | -h | --help | -H | --help-full | -L | --list-files | \
                --version | --config)
                    return 0
                    ;;
                
                # options requiring fixed string
                --color)
                    COMPREPLY=($(\compgen -W "auto always never" -- "$curr"))
                    return $?
                    ;;
            esac

            # a list file name has already been confirmed
            if [[ $COMP_LINE =~ \ (-[a-zA-Z0-9]*[UR]|--remove-list-file|--use)\ +[a-zA-Z0-9_]+\ + ]]; then
                return 0
            
            # the user is inputting a new value
            elif [[ $prev =~ ^(-[a-zA-Z0-9]*[an]|--add|--number)$ ]] ; then
                COMPREPLY=
                return 0

            # complements option name
            elif [[ $curr =~ ^- ]] ; then
                COMPREPLY=($(\compgen -W "
                    -a --add
                    -A --add-forced
                    -B --builtin-cd
                    -c --check
                    -C --clean	
                    -e --edit
                    -E --cmd-editor
                    -F --cmd-filter
                    -f --filter
                    -h --help
                    -H --help-full
                    -l --list
                    -L --list-files
                    -n --number
                    -o --open
                    -O --cmd-open
                    -p --path
                    -r --remove
                    -R --remove-list
                    -m --multiplexer
                    -s --subdir
                    -U --use
                    -u --use-temp
                    -v --verbose
                    --version
                    --list-names
                    --list-paths
                    --color
                    --config
                    --show-config 
                    " -- "$curr"))
                return $?

            # complements a list file name
            elif [[ $prev =~ ^(-[a-zA-Z0-9]*[uUR]|--remove-list-file|--use(-temp)?|--remove-list)$ ]]; then
                COMPREPLY=($(\compgen -W "$(cda -L --color never | \sed 's/^..//')" -- "$curr"))
                return $?

            # complements a command name
            elif [[ $prev =~ ^(-[a-zA-Z0-9]*[EFO]|--cmd-(editor|filter|open))$ ]] ; then
                COMPREPLY=($(\compgen -c -- "$curr"))
                return $?
            fi
        fi

        # complements a directory path
        if [[ $curr =~ (/|^[.~]/?) || $COMP_LINE =~ \ (-[a-zA-Z0-9]*[aA]|--add(-forced)?)\ +[a-zA-Z0-9_]+\  ]]; then
            COMPREPLY=($(\compgen -- "$curr"))
            return $? 

        # complements an alias name
        else
            # -m --multiplexer
            if [[ $COMP_LINE =~ \ (-[a-zA-Z0-9]*m[a-zA-Z0-9]*|--multiplexer)\  ]]; then
                [[ $COMP_LINE =~ \ [a-zA-Z0-9_]+\  ]] && return 0
                COMPREPLY=($(\compgen -W "$(cda -m --list-names  2>/dev/null)" -- "$curr"))
                return $?

            # -u use-temp
            elif [[ $COMP_LINE =~ \ (-[a-zA-Z0-9]*u|--use-temp)\ +[a-zA-Z0-9_]+\ + ]]; then
                local using="$(\sed -e 's/^.* \{1,\}\(-[a-zA-Z0-9]*u\|--use-temp\) \{1,\}\([a-zA-Z0-9_]+\) \{1,\}.*$/\2/' <<< "$COMP_LINE")"
                COMPREPLY=($(\compgen -W "$(cda -u $using --list-names  2>/dev/null)" -- "$curr"))
                return $?

            # aliases in the current list
            else
                COMPREPLY=($(\compgen -W "$(cda --list-names  2>/dev/null)" -- "$curr"))
                return $?
            fi
        fi
    }

    if [[ -n ${ZSH_VERSION-} ]]; then
        autoload -U +X bashcompinit && bashcompinit
    fi

    \complete -o default -o dirnames -F _cda cda
fi
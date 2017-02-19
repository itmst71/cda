# cda
`cd` with an alias name.

# Demo
![cda demo](https://github.com/itmst71/cda/wiki/images/demo.gif)

# Contents
* [Demo](#demo)
* [Contents](#contents)
* [Features](#features)
* [Requirements](#requirements)
* [Installation](#installation)
* [Usage](#usage)
    * [Entry Level](#entry-level)
    * [Basic Level](#basic-level)
    * [Intermediate Level](#intermediate-level)
    * [Advanced Level](#advanced-level)
* [Config Variables](#config-variables)
* [License](#license)

# Features
* Executes `cd` with an alias name
* Manages alias names in a text file
* Supports interactive filters like `percol`, `peco`, `fzf`, `fzy` etc...
* Supports `bash-completion`
* Supports terminal multiplexers (`tmux` and `GNU screen`)

# Requirements
* Bash 3.2+ / Zsh 5.0+
* Some POSIX commands

**Optional**  
* Interactive filters like `percol`, `peco`, `fzf`, `fzy` etc...
* bash-completion

# Installation
* `git clone`
```console
$ git clone https://github.com/itmst71/cda.git
```

* `source cda.sh` in `~/.bashrc` or `~/.zshrc`
```bash
[[ -f "/path/to/cda/cda.sh" ]] && . /path/to/cda/cda.sh
```

# Usage
## Entry Level
### Basic Options
* `-a` `--add` adds an alias.
```console
$ cda -a foo /baz/bar/foo
```

* Execute `cd` with an alias name.
```console
$ cda foo
$ pwd
/baz/bar/foo
```

* `cda` accepts incomplete alias names if they are unique in forward match search.
```console
$ cda f
$ pwd
/baz/bar/foo
```

* Complement alias name with `TAB` key.
```console
$ cda f<TAB>
$ cda foo
```

* `-l` `--list` shows the list.
```console
$ cda -l
foo         /baz/bar/foo
```

* Omitting the path when adding, the current directory will be used.
```console
$ pwd
/baz/bar
$ cda -a bar
$ cda -l
bar         /baz/bar
foo         /baz/bar/foo
```

* `-r` `--remove` removes an alias.
```console
$ cda -r bar
$ cda -l
foo         /baz/bar/foo
```

* `-e` `--edit` opens the list in a text editor.
```console
$ cda -e
```

* `-h` `--help` shows basic help. `-H` `--help-full` shows full help with `less`.
```console
$ cda -h
```

## Basic Level
### External Interactive Filter
* You can use external interactive filter commands to select an alias name.  
By default, multiple filter command names separated by colons are set to the variable `CDA_CMD_FILTER`.  
The first available command will be used.
```console
CDA_CMD_FILTER=percol:peco:fzf:fzy
```
This value can be changed in the configuration file `~/.cda/config`.  
`--config` opens the file in a text editor.
```console
$ cda --config
```

* If no alias name is given, the entire list is passed to the filter.
```console
$ cda
QUERY>                                       (1/5) [1/1]
:bar         /baz/bar
:baz         /baz
:foo         /baz/bar/foo
:foo2        /qux/baz/bar/foo
:foo2_2      /quux/qux/baz/bar/foo
```

* If the specified alias name matches multiple aliases, only those are passed to the filter.
```console
$ cda f
QUERY>                                       (1/3) [1/1]
:foo         /baz/bar/foo
:foo2        /qux/baz/bar/foo
:foo2_2      /quux/qux/baz/bar/foo 
```
        
* If there is an exact match alias, it will be used.
```console
$ cda foo2
$ pwd
/qux/baz/bar/foo
```

* `-f` `--filter` forces to use the filter even if there is an exact match alias.
```console
$ cda foo2 -f
QUERY>                                       (1/2) [1/1]
:foo2        /qux/baz/bar/foo
:foo2_2      /quux/qux/baz/bar/foo
```

* `-F` `--cmd-filter` can override `CDA_CMD_FILTER` variable.
```console
$ cda -F fzf
  :foo2_2      /quux/qux/baz/bar/foo
  :foo2        /qux/baz/bar/foo
  :foo         /baz/bar/foo
  :baz         /baz
> :bar         /baz/bar
  5/5
> 
```

### Internal Filter
* `cda` itself also has the simple non-interactive filter.  
***The first argument is always used for forward match searches.***
```console
$ cda -l
abcefg1       /qux/baz/bar/foo1
abcgfe1       /qux/baz/bar/foo2
abcabcefg1    /qux/baz/bar/foo3
axcxyz1       /qux/baz/bar/foo4
axcxyz11      /qux/baz/bar/foo5
axcxyz121     /qux/baz/bar/foo6
bbcefg1       /qux/baz/bar/foo7
$ cda -l b
bbcefg1       /qux/baz/bar/foo7
```

* The second and subsequent arguments are used for unordered partial AND match search after forward match search with the first argument.
```console
$ cda -l a f
abcefg1       /qux/baz/bar/foo1
abcgfe1       /qux/baz/bar/foo2
abcabcefg1    /qux/baz/bar/foo3
$ cda -l a f a
abcabcefg1    /qux/baz/bar/foo3
$ cda -l ax 11
axcxyz11      /qux/baz/bar/foo5
$ cda a 2
$ pwd
/qux/baz/bar/foo6
```

## Intermediate Level
### Pipe
* `cda` supports pipe input. But note that ***`cd` via a pipe works only in `Zsh`***.  
```console
$ echo foo | cda      # works in Zsh only
```

* Functions that do not need to be executed in the current shell also work in `Bash`.
```console
$ printf -- "%s\n" -a foo /baz/bar/foo | cda  # add an alias
$ echo foo | cda -p                           # print the path
/baz/bar/foo
```

### List Files
* `cda` can easily switch multiple list files being in `~/.cda/lists`.

* `-L` `--list-files` shows the list files.
```console
$ cda -L
* default
  mylist
```

* `-U` `--use` switches the list file to use by default.  
If the list specified does not exist, it will be created.
```console
$ cda -U mylist
Using: /Users/me/.cda/lists/mylist
$ cda -L
  default
* mylist
```

* `-u` `--use-temp` temporarily switches the list file to use.
```console
$ cda -a foo /baz/bar/foo
$ cda -a foo /qux/baz/bar/foo -u mylist
$ cda foo -u mylist
$ pwd
/qux/baz/bar/foo
$ cda foo
$ pwd
/baz/bar/foo
```

* `-R` `--remove-list` removes the specified list file.
```console
$ cda -R mylist
$ cda -L
* default
```

### Open Command
* `-o` `--open` opens the alias path with a file manager or something.
```console
$ cda -o foo2_2
```

* By default, multiple open command names separated by colons are set to the variable `CDA_CMD_OPEN`.  
The first available command will be used.
```console
CDA_CMD_OPEN=xdg-open:open:ranger:mc
```

* `-O` `--cmd-open` can override `CDA_CMD_OPEN` value.
```console
$ cda foo -oO ranger
```

## Advanced Level
### Subdirectory Mode
* Accepts the directory path if a filter is available.   
Assigns numbers to subdirectories in the argument directory and passes them to the filter.  
So you can narrow them down to `cd` by number.
```console
$ cda ./troublesome_names_for_input
QUERY>                                       (1/7) [1/1]
:0       .
:1       অসমীয়া
:2       Հայերեն
:3       한국어
:4       عربي
:5       English
:6       日本語
```

* If the argument does not contain a hint that it is a file path like `/` or `.`, it will be treated as an alias name.  
So to specify a relative path in the current directory, do as follows.
```console
$ cda ./foo
```

* `-s` `--subdir` invokes the subdirectory mode with an alias name.
```console
$ cda -s foo
QUERY>                                       (1/4) [1/1]
:0       .
:1       subdir1_of_foo
:2       subdir2_of_foo
:3       subdir3_of_foo
```

* `-s` `--subdir` is equivalent to following 2 examples
```console
$ cda foo
$ cda .
QUERY>                                       (1/4) [1/1]
:0       .
:1       subdir1_of_foo
:2       subdir2_of_foo
:3       subdir3_of_foo
```

```console
$ cda "`cda -p foo`"
QUERY>                                       (1/4) [1/1]
:0       .
:1       subdir1_of_foo
:2       subdir2_of_foo
:3       subdir3_of_foo
```

* If you specify a subdirectory number with the second argument, you can confirm the selection without the filter.
```console
$ cda ./troublesome_names_for_input 2
$ pwd
/home/user/troublesome_names_for_input/Հայերեն
```

* If you invoke the subdirectory mode with `-s` `--subdir`, specify a number with `-n` `--number`.
```console
$ cda -s troublesome -n 6
$ pwd
/home/user/troublesome_names_for_input/日本語
```

### Auto-Alias for Terminal Multiplexer
* When `cd` in `tmux` or `GNU screen` session, alias is automatically added / removed using session name, window number and pane number.  
So you can easily `cd` by using aliases added in another session or another window.

* This feature can be enabled by setting `CDA_AUTO_ALIAS` to `true`.

* `-m` `--multiplexer` temporarily switches to auto alias list for terminal multiplexer.
```console
$ tmux ls
dev1: 1 windows (created Tue Feb 07 01:24:11 2017) [80x19] (attatched)
ssh: 1 windows (created Tue Feb 07 01:24:33 2017) [80x19] (attatched)
$ screen -ls
There is a screen on:
        306.dev2        (Attached)
        6434.pts-13.myhost     (Attached)
1 Socket in /tmp/uscreens/S-itmst71.
$ cda -m -l
13_0            /baz/bar
dev1_0_0        /baz
dev1_0_1        /baz/bar/foo
dev2_0          /quux/qux/baz2/bar/foo
dev2_1          /qux/baz/bar/foo
ssh_0_0         /quux/qux/baz/bar/foo
$ cda -m dev2_0
$ pwd
/quux/qux/baz2/bar/foo
```

* Of course you can use tab completion and filters.
```console
$ cda -m d<TAB>
$ cda -m dev
QUERY>                                       (1/4) [1/1]
:dev1_0_0        /baz
:dev1_0_1        /baz/bar/foo
:dev2_0          /quux/qux/baz2/bar/foo
:dev2_1          /qux/baz/bar/foo
```

* If you specify `-` as the alias name, you can `cd` to the directory you executed `cd` last in all sessions.
```console
$ cda -m -
```

* The auto-alias list and auto-pwd file are automatically created in `~/.cda/lists` as `.autolist` and `.autopwd` respectively.
```console
$ ls -a ~/.cda/lists
.  ..  .autolist  .autopwd  default
```

* The auto-alias is realized by hooking `cd`.  
You can change the hook type with the `CDA_AUTO_ALIAS_HOOK_TYPE` variable.

# Config Variables
## Specification
* By default, configuration variables can be defined with the following file:

        ~/.cda/config

* You can specify multiple commands candidates with separating with `:`. The first available command will be used.

        CMD_VAR=cmd1:cmd2:cmd3

* If you want to sepecify in a full-path including spaces or use with options, write with `'"..."'` like below.

        CMD_VAR=cmd1:'"/the path/to/cmd" -a --long="a b"':cmd3

* For boolean-like variables, set one of the following values.  
Truthy : [`true`, `yes`, `y`, `enabled`, `enable`, `on` ]  
Falsy  : [ `false`, `no`, `n`, `disabled`, `disable`, `off` ]  
They are not case sensitive.

        BOOL_VAR=true

## Variables
* CDA_DATA_ROOT  
Specify the path to the user data directory, which ***must be set before `source cda.sh`***.  
***So it should be written in `~/.bashrc` or `~/.zshrc`*** instead of the config file.

        CDA_DATA_ROOT=$HOME/.cda

* CDA_BASH_COMPLETION  
Set to `false` if you don't want to use Bash-Completion.  
Default is `true`.

        CDA_BASH_COMPLETION=true

* CDA_CMD_FILTER  
Specify the name or path of interactive filter commands to select an alias from list when no argument is given or multiple aliases are hit.  
`-F` `--cmd-filter` can override this.

        CDA_CMD_FILTER=percol:peco:fzf:fzy

* CDA_CMD_OPEN  
Specify the name or path of file manager commands to open the path when using `-o` `--open`.  
`-O` `--cmd-open` can override this.

        CDA_CMD_OPEN=xdg-open:open:ranger:mc

* CDA_CMD_EDITOR  
Specify a name or path of editor commands to edit the list file with `-e` `--edit` or the config file with `--config`.  
`-E --cmd-editor` can override this.

        CDA_CMD_EDITOR=vim:nano:emacs:vi

* CDA_BUILTIN_CD  
Set to `true` if you do not want to affect or be affected by external cd extension tools.  
`-B` `--builtin-cd` can override this and temporarily set to `true`. Default is `false`.

        CDA_BUILTIN_CD=false

* CDA_AUTO_ALIAS  
Set to `true` if you want to use the [auto-alias feature](#auto-alias-for-terminal-multiplexer).  
Default is `false`.

        CDA_AUTO_ALIAS=false

* CDA_AUTO_ALIAS_HOOK_TYPE  
Specify one of [`function`, `prompt`, `chpwd`] as the hook type for the auto-alias feature which is realized by hooking `cd`.  
`function` overrides `cd` command with the `Bash` function.  
`prompt` adds the hook function to `PROMPT_COMMAND` variable.  
`chpwd` adds the hook function with `add-zsh-hook`. Only `Zsh` can use `chpwd`.

        CDA_AUTO_ALIAS_HOOK_TYPE=function     # Bash
        CDA_AUTO_ALIAS_HOOK_TYPE=chpwd        # Zsh

* CDA_COLOR_MODE  
Specify one of [`never`, `always`, `auto`] as the color mode of the output message.  
When `auto` is selected, it will automatically switch whether or not to color the message depending on whether the output destination is a `TTY` or not.  
`--color` can override this.

        CDA_COLOR_MODE=auto

* CDA_LIST_HIGHLIGHT_COLOR  
Specify the value part of the ANSI escape sequence color codes.  
For example, in case of color codes `\033[4;1;32m`, specify only `4;1;32`.

        CDA_LIST_HIGHLIGHT_COLOR="0;0;32"
        
* CDA_ALIAS_MAX_LEN  
Specify the maximum number of characters for the alias name.  
If you change the value you can reformat the list with the new value with `--clean`.

        CDA_ALIAS_MAX_LEN=16


# License
MIT

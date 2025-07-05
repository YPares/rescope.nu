# PROmpt broWSER
#
# Open and navigate directories directly from your prompt, and
# browse your files with an extensible fzf-based fuzzy finder
#
# Builds upon nushell's 'std dirs'

use std/dirs
export use path.nu

export-env {
  use std/dirs

  $env.prowser = {
    __previous_dirs_state: null
    __current_snap_name: null
    depth: 999
    excluded: [
      "**/.*/*/**" # Do not recurse into dot directories
    ]
  }
}

const snaps_file = "~/.config/nushell/dirs-snapshots.nuon" | path expand -n


export def --env reset [] {
  cd ($env.DIRS_LIST | get $env.DIRS_POSITION)
}

export def --env accept [] {
  $env.DIRS_LIST = $env.DIRS_LIST | update $env.DIRS_POSITION $env.PWD
}

export def --env left [] {
  reset
  dirs prev
}

export def --env right [] {
  reset
  dirs next
}

export def --env up [] {
  cd ..
}

def add-left --env [args] {
  match $env.DIRS_POSITION {
    0 => {
      $env.DIRS_LIST = $args ++ $env.DIRS_LIST
    }
    _ => {
      $env.DIRS_LIST = (
        ($env.DIRS_LIST | slice ..($env.DIRS_POSITION - 1)) ++
        $args ++
        ($env.DIRS_LIST | slice $env.DIRS_POSITION..)
      )
    }
  }
  $env.DIRS_POSITION += ($args | length)
  reset
}

def add-right --env [args] {
  $env.DIRS_LIST = (
    ($env.DIRS_LIST | slice ..$env.DIRS_POSITION) ++
    $args ++
    ($env.DIRS_LIST | slice ($env.DIRS_POSITION + 1)..)
  )
}

export def --env add [--left (-l), ...args] {
  let args = $args | path expand -n
  if $left {
    add-left $args
  } else {
    add-right $args
  }
}

export def --env drop [--others (-o)] {
  if $others {
    $env.DIRS_LIST = [($env.DIRS_LIST | get $env.DIRS_POSITION)]
    $env.DIRS_POSITION = 0
  } else {
    $env.DIRS_LIST = match $env.DIRS_POSITION {
      0 if ($env.DIRS_LIST | length) == 1 => $env.DIRS_LIST
      0 => ($env.DIRS_LIST | slice 1..)
      $p if $p + 1 == ($env.DIRS_LIST | length) => {
        $env.DIRS_POSITION -= 1
        ($env.DIRS_LIST | slice ..-2)
      }
      _ => (
        ($env.DIRS_LIST | slice ..($env.DIRS_POSITION - 1)) ++
        ($env.DIRS_LIST | slice ($env.DIRS_POSITION + 1)..)
      )
    }
    cd ($env.DIRS_LIST | get $env.DIRS_POSITION)
  }
}

def --env __each [closure: closure] {
  $env.DIRS_LIST | each {|dir|
    cd $dir
    {index: $dir, out: ($dir | do $closure $dir)}
  }
}

def --env __par-each [closure: closure] {
  $env.DIRS_LIST | par-each {|dir|
    cd $dir
    {index: $dir, out: ($dir | do $closure $dir)}
  }
}

export def "snap current-state" [] {
  {list: $env.DIRS_LIST, pos: $env.DIRS_POSITION, name: $env.prowser.__current_snap_name}
}

def "snap saved" [] {
  try { open $snaps_file } catch { {} }
}

export def "snap complete" [] {
  snap saved | transpose value description |
    update description {
      get list | each {path basename} | str join ", "
    }
}

# List all snaps recorded to disk
export def "snap list" [] {
  snap saved | transpose index v | flatten v
}

def --env "snap set" [name snap] {
  $env.prowser.__current_snap_name = $name
  $env.DIRS_LIST = $snap.list
  $env.DIRS_POSITION = $snap.pos
  reset
}

# Save and load dirs states ("snaps") to/from disk
#
# Will load a snap if called with no flags
export def --env snap [
  name?: string@"snap complete"
    # A name for the snap. Will target the last used snap if not given, or
    # "default" if no snap has been loaded/saved in the current shell 
  --write (-w) # Write a snap (write current dirs state to disk)
  --delete (-d) # Delete a snap from disk
  --previous (-p) # Reset dirs state to the one before last snap was loaded
] {
  let name = $name | default $env.prowser.__current_snap_name? | default "default"
  if $write {
    accept
    snap saved |
      upsert $name (snap current-state | reject name) |
      save -f $snaps_file
    print $"Saved to snapshot '($name)'"
    $env.prowser.__current_snap_name = $name
  } else if $delete {
    snap saved | reject $name | save -f $snaps_file
    print $"Deleted snapshot '($name)'"
    if $name == $env.prowser.__current_snap_name {
      $env.prowser.__current_snap_name = "default"
    }
  } else if $previous {
    let state_to_restore = $env.prowser.__previous_dirs_state
    $env.prowser.__previous_dirs_state = snap current-state
    if $state_to_restore != null {
      let name_to_restore = $state_to_restore.name?
      snap set $name_to_restore $state_to_restore
      print $"Back to previous state \(was based on snap '($name_to_restore)')"
    } else {
      error make {msg: "No previous snap known in this shell"}
    }
  } else {
    let verb = if $name == $env.prowser.__current_snap_name {"Reloaded"} else {"Loaded"}
    $env.prowser.__previous_dirs_state = snap current-state
    snap set $name (snap saved | get $name)
    print $"($verb) snapshot '($name)'"
  }
}

export def --env toggle-depth [] {
  $env.prowser.depth = match $env.prowser.depth {
    1 => 999
    _ => 1
  }
}

export def "glob all" [] {
  glob -l -d $env.prowser.depth -e $env.prowser.excluded $in
}

export def "glob files" [] {
  glob -lD -d $env.prowser.depth -e $env.prowser.excluded $in
}

export def "glob dirs" [] {
  glob -lF -d $env.prowser.depth -e $env.prowser.excluded $in
}

export def select-paths [multi: bool, --prompt: string] {
  each {|p|
    let type = $p | path expand | path type
    let clr = if $type == "dir" {"blue"} else {"default"}
    [ $"(ansi $clr)($p)(ansi reset)(char fs)"
      $"(ansi attr_dimmed)(ansi attr_italic)($type)(ansi reset)"
    ] | str join " "
  } |
  str join "\n" | (
    fzf --height=40 --reverse --style default --info inline-right
        ...(if $prompt != null {[--prompt $"($prompt)> "]} else {[]})
        --ansi --color "pointer:magenta,marker:green"
        --tiebreak end
        --delimiter (char fs) --with-nth 1 --accept-nth 1
        --cycle --exit-0 --select-1
        --keep-right
        --preview $"
          echo -n '(ansi attr_italic)(ansi attr_underline)'
          if [ {2} == dir ]; then
            echo (ansi blue){1}(ansi reset)
            \( ls --color {1} | awk '{ print \" ↳ \" $0 }' )
          else
            echo {1}:(ansi reset)
            echo ""
            bat --color always --terminal-width $FZF_PREVIEW_COLUMNS {1}
          fi
        "
        --preview-window "right,60%,noinfo,border-left"
        --color "scrollbar:blue"
        --bind "ctrl-c:cancel,alt-c:cancel,alt-z:cancel,alt-q:abort"
        --bind "alt-h:first,alt-j:down,alt-k:up,alt-l:accept"
        --bind "alt-left:first,alt-right:accept,alt-up:half-page-up,alt-down:half-page-down"
        --bind "ctrl-alt-k:half-page-up,ctrl-alt-j:half-page-down"
        --bind "alt-backspace:clear-query"
        --bind "ctrl-space:jump"
        --bind "ctrl-a:toggle-all"
        --bind "ctrl-s:half-page-down,ctrl-z:half-page-up"
        --bind "ctrl-d:preview-half-page-down,ctrl-e:preview-half-page-up"
        --bind "ctrl-w:toggle-preview-wrap"
        --bind "resize:execute(tput reset)"
        ...(if $multi {[--multi]} else {[--bind "tab:accept"]})
  ) | lines
}

# Run an fzf-based file fuzzy finder on the paths listed by some closure
#
# If the commandline is empty, it will open the selected files. If not, it will
# act as an auto-completer
#
# Set $env.prowser.excluded to select which patterns should be excluded
export def --env browse [
  glob: closure
  --multi
  --prompt: string
  --ignore-command
  --relative-to: path = "."
] {
  let cmd = if $ignore_command {""} else {
    commandline
  }
  let empty_cmd = $cmd | str trim | is-empty
  let prompt = $"(if $empty_cmd {'open'} else {'complete'})(if $prompt != null {$"\(($prompt))"} else {""})"
  let elems_before = $cmd |
    str substring 0..(commandline get-cursor) |
    split row -r '\s+'
  let arg = match ($elems_before | reverse) {
    [] => [$env.PWD "**/*"]
    [$x ..$_] => {
      if ($x | path type) == "dir" {
        [$x "**/*"]
      } else {
        [($x | path dirname) $"($x | path basename)*/**"]
      }
    }
  }
  let selected = do {
    cd $arg.0
    let relative_to = $relative_to | path expand -n
    $arg.1 | do $glob | do {
      cd $relative_to
      $in | path relative-to $env.PWD |
        where {is-not-empty} |
        select-paths $multi --prompt $prompt |
        path expand -n
    }
  }
  let selected_types = $selected | each {path expand | path type} | uniq
  match [$empty_cmd $selected $selected_types] {
    [_ [] _] => {}
    [true [$path] [dir]] => {
      cd $path
    }
    [true [$dir ..$rest] [dir]] => {
      cd $dir
      add ...$rest
    }
    [true _ [file]] => {
      [{command: ([$env.EDITOR ...$selected] | str join " "), cwd: $env.PWD}] | history import
      run-external $env.EDITOR ...$selected
    }
    _ => {
      commandline edit -r ($elems_before | slice 0..-2 | append $selected | str join " ")
      commandline set-cursor --end
    }
  }
}

export def --env down [] {
  browse --multi --prompt dirs --ignore-command {glob dirs}
}

# To be called in your PROMPT_COMMAND
#
# Shows the opened dirs and highlights the current ones
export def render [] {
  let width = (term size).columns

  let ds = dirs
  let reverse_bit = if ($ds | length) == 1 {""} else {"_reverse"}
  $ds | each {|d|
    let color = if $d.active {
      if $d.path == ($env.DIRS_LIST | get $env.DIRS_POSITION) {
        $"light_green($reverse_bit)"
      } else {
        $"yellow($reverse_bit)"
      }
    } else {
      "default_dimmed"
    }
    $d.path | path shorten --slice (
      if $d.active {
        if $width >= 160 or ($ds | length) <= 2 {
          (-3..)
        } else if $width >= 80 and ($ds | length) <= 4 {
          (-2..)
        } else {
          (-1..)
        }
      } else {
        (-1..)
      }
    ) | $"(ansi ($color))($in)(ansi reset)"
  } |
    str join $"(ansi yellow)|(ansi reset)" |
    $"(ansi reset)(if $env.prowser.depth == 1 {'[↳1]'})($in)"
}

# To be called in your TRANSIENT_PROMPT_COMMAND
export def render-transient [] {
  $env.PWD | path shorten --slice (
    if ((term size).columns >= 120) {
      (-5..)
    } else {
      (-3..)
    }
  )
}

export def sort-by-mod-date [] {
  each {ls -lD $in} | flatten | sort-by -r modified | get name
}

def cmd [cmd] {
  {send: ExecuteHostCommand, cmd: $cmd}
}

# To be added to your $env.config.keybindings in your config.nu
export def default-keybindings [
  --prefix = "prowser "
    # Set this depending on how prowser is imported in your config.nu
] {
  [
    [modifier keycode        event];

    [control  char_f         (cmd $'($prefix)browse --multi --prompt all {($prefix)glob all}')]
    [alt      char_f         (cmd $'($prefix)browse --multi --prompt by-mod-date {($prefix)glob files | ($prefix)sort-by-mod-date}')]
    [alt      char_r         (cmd $'($prefix)toggle-depth')]
    [alt      [left char_h]  (cmd $'($prefix)left')]
    [alt      [right char_l] (cmd $'($prefix)right')]
    [alt      [up char_k]    (cmd $'($prefix)up')]
    [alt      [char_j down]  (cmd $'($prefix)down')]
    [alt      char_s         (cmd $'($prefix)accept')]
    [alt      char_z         (cmd $'($prefix)reset')]
    [alt      char_d         (cmd $'($prefix)drop')]
    [alt      char_q         (cmd $'($prefix)drop --others')]
    [alt      char_c         (cmd $'($prefix)add $env.PWD; ($prefix)right')]
    [alt      char_x         (cmd $'($prefix)add --left $env.PWD; ($prefix)left')]
  ] | insert mode emacs | flatten modifier keycode
}

export alias each = __each
export alias par-each = __par-each

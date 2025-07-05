export def shorten [--slice: range] {
  str replace $env.HOME "~" | if $slice != null {
    path split | slice $slice | path join
  } else { $in }
}

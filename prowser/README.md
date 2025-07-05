# prowser

A prompt-based browser for Nushell.

Minimal setup to add to your `config.nu`:

```nushell
## In your ~/.config/nushell/config.nu

use path/to/prowser

$env.PROMPT_COMMAND = {||
  $"...(prowser render)..."
}

$env.config.keybindings = [
  ...
] ++ (prowser default-keybindings)
```

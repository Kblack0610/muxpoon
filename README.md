# muxpoon

Pin tmux windows to numbered slots and jump to them with one key, on any tmux server you run. It does for tmux windows what the [harpoon](https://github.com/ThePrimeagen/harpoon) plugin does for Neovim buffers.

Press `Prefix+a` in a window and it takes the next slot. `M-1` takes you back to slot 1 from anywhere, including from a different tmux server. `Prefix+e` opens the list in your editor, where you reorder lines to renumber and delete a line to unpin.

The list is a plain file, so pins survive `kill-server` and a reboot. A window that no longer exists falls back to its session.

It needs tmux 3.2 or later and bash. CI runs it on Linux; macOS is untested.

## Install

With [TPM](https://github.com/tmux-plugins/tpm), add this to `tmux.conf` and press `Prefix+I`:

```tmux
set -g @plugin 'Kblack0610/muxpoon'
```

Without TPM, clone it anywhere:

```sh
git clone https://github.com/Kblack0610/muxpoon ~/.tmux/plugins/muxpoon
```

Then add one line to `tmux.conf`, below any `@muxpoon-*` options, and reload:

```tmux
run-shell ~/.tmux/plugins/muxpoon/muxpoon.tmux
```

## Keys

| Key | Does |
|---|---|
| `Prefix+a`, `Prefix+C-a` | Pin this window, or unpin it if it is pinned |
| `M-1` to `M-4` | Jump to that slot (no prefix) |
| `Prefix+e` | Edit the list in `$EDITOR`, in a popup |

Each bind carries a `-N` note, so `Prefix+?` (`tmux list-keys -N`) lists these keys with the rest of tmux's.

If your prefix is `C-a`, you probably want `C-a` to keep sending the prefix: set `@muxpoon-toggle-keys` to `a`.

## Options

Set these before the plugin loads. The value `none` turns off a group of keys.

| Option | Default | Meaning |
|---|---|---|
| `@muxpoon-toggle-keys` | `a C-a` | Prefix keys that pin and unpin, space separated |
| `@muxpoon-menu-keys` | `e` | Prefix keys that open the list |
| `@muxpoon-jump-modifier` | `M-` | What goes before the slot number in a jump key |
| `@muxpoon-slots` | `4` | How many jump keys to bind, 1 to 9 |
| `@muxpoon-popup-width` | `80%` | Width of the list popup |
| `@muxpoon-popup-height` | `60%` | Height of the list popup |
| `@muxpoon-file` | see below | Where the list lives |
| `@muxpoon-goto` | none | A command for jumps a plain attach cannot do |

`@muxpoon-slots` only sets how many keys are bound. The list can grow past that, and `muxpoon jump 7` works from a shell or a binding of your own.

An example that moves everything:

```tmux
set -g @muxpoon-toggle-keys 'p'
set -g @muxpoon-jump-modifier 'C-'
set -g @muxpoon-slots 6
```

## The slot file

The list is at `$XDG_STATE_HOME/muxpoon/slots`, which is `~/.local/state/muxpoon/slots` by default. `@muxpoon-file` moves it, and the `MUXPOON_FILE` environment variable overrides both. Outside tmux there is no server to ask for the option, so `muxpoon ls` from a plain shell needs `MUXPOON_FILE` if you moved the file.

Each line is one slot and the line number is the slot number. Fields are separated by tabs:

```
server  session  window_id  session_created  window_name
```

| Field | Meaning |
|---|---|
| `server` | The `-L` socket name, or the full socket path for a server started with `-S` outside tmux's own directory |
| `session` | The session name |
| `window_id` | The tmux window id, such as `@3` |
| `session_created` | The session's creation time, in epoch seconds |
| `window_name` | A label for `muxpoon ls`, never matched |

tmux restarts window ids after `kill-server`, so `@3` can come back as a different window. A jump only trusts the id while `session_created` still matches. If it does not, or the window has closed, you land on the session.

A line with only `server` and `session` is a session pin. You can add one by hand in the menu.

## Jumping between servers

A tmux client cannot move to another server. To cross, muxpoon selects the slot's window over there, then runs `detach-client -E`, which replaces your client with a new one attached to the target. Nothing else has to be installed.

If you have your own way of reaching a session, such as a script that starts it when it is not running, name it in `@muxpoon-goto`:

```tmux
set -g @muxpoon-goto 'my-session-hopper goto'
```

muxpoon runs it with two more arguments, the server and either `session` or `session:window_id`, whenever a jump cannot be a plain `switch-client`. If the first word of the option is not on `PATH`, muxpoon ignores it and does the attach itself.

## Command line

```
muxpoon toggle     pin or unpin this window
muxpoon jump <n>   jump to slot n
muxpoon menu       edit the list in $EDITOR
muxpoon ls         print the slots
muxpoon file       print the list's path
```

## Tests

```sh
bats test
MUXPOON_REAL_TMUX=1 bats test
```

The first line uses a recording stub in place of tmux. The second also starts real servers and presses real keys, so keep it to a container or CI.

## License

MIT. See [LICENSE](LICENSE).

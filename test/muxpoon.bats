#!/usr/bin/env bats
# muxpoon against the recording tmux: each jump assertion is "which command did it issue".
# test/real.bats runs the same paths on real servers.

bats_require_minimum_version 1.5.0

setup() {
  load helper
  stub_init
}

# at <server> <session> [window_id [session_created [name]]] -- where the stub says this
# client is sitting.
at() {
  export STUB_SOCKET="/tmp/tmux-$(id -u)/$1" STUB_SESSION="$2" \
    STUB_WINDOW_ID="${3:-@7}" STUB_SESSION_CREATED="${4:-1000}" STUB_WINDOW_NAME="${5:-sh}"
}

# pinned <server> <session> ... -- 2-field lines: plain session pins.
pinned() {
  mkdir -p "${LIST%/*}"
  : > "$LIST"
  while [ $# -gt 0 ]; do
    printf '%s\t%s\n' "$1" "$2" >> "$LIST"
    shift 2
  done
}

# pinw <server> <session> <window_id> <stamp> <name> -- append one window pin.
pinw() {
  mkdir -p "${LIST%/*}"
  printf '%s\t%s\t%s\t%s\t%s\n' "$@" >> "$LIST"
}

# windows [<server>] -- the live windows list-windows reports, rows read from stdin.
windows() { cat > "$STUB_DIR/windows${1:+.$1}"; }

# hook <name> -- put a command on PATH and name it in @muxpoon-goto; it records its args.
hook() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  printf '#!/bin/sh\necho "%s $*" >> "$STUB_DIR/calls.log"\n' "$1" > "$BATS_TEST_TMPDIR/bin/$1"
  chmod +x "$BATS_TEST_TMPDIR/bin/$1"
  PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  printf '%s go\n' "$1" > "$STUB_DIR/opt.goto"
}

@test "toggle appends the current window, keyed by server, session, id and stamp" {
  at red api
  run "$M" toggle
  [ "$status" -eq 0 ]
  shows "api:sh -> slot 1"
  at blue web @3 2000 vim
  run "$M" toggle
  shows "web:vim -> slot 2"
  [ "$(cat "$LIST")" = "$(printf 'red\tapi\t@7\t1000\tsh\nblue\tweb\t@3\t2000\tvim')" ]
}

@test "two windows of one session take two slots" {
  at red api @1 1000 sh
  run "$M" toggle
  at red api @2 1000 vim
  run "$M" toggle
  shows "api:vim -> slot 2"
  [ "$(wc -l < "$LIST" | tr -d ' ')" = 2 ]
}

@test "toggle on a pinned window unpins it and closes the gap" {
  pinw red api @1 1000 sh
  pinw blue web @3 1000 vim
  pinw red docs @4 1000 sh
  at blue web @3 1000 renamed-since
  run "$M" toggle
  [ "$status" -eq 0 ]
  shows "unpinned web:renamed-since"
  [ "$(cut -f2 "$LIST" | tr '\n' ' ')" = "api docs " ]
}

@test "a session of the same name on another server is a different pin" {
  pinw red web @7 1000 sh
  at blue web
  run "$M" toggle
  shows "web:sh -> slot 2"
}

@test "a socket outside tmux's directory is kept by path" {
  export STUB_SOCKET="/run/sockets/odd" STUB_SESSION=api
  run "$M" toggle
  [ "$(cut -f1 "$LIST")" = "/run/sockets/odd" ]
}

@test "toggle outside tmux says so and exits 0" {
  unset TMUX
  run "$M" toggle
  [ "$status" -eq 0 ]
  says "not inside tmux"
}

@test "jump to a live window selects it, then switches to its session" {
  pinw red api @1 1000 sh
  pinw red api @2 1000 vim
  printf '1000\t@1\tsh\n1000\t@2\tvim\n' | windows
  at red api @1
  run "$M" jump 2
  [ "$status" -eq 0 ]
  called 'tmux select-window -t =api:@2'
  called 'tmux switch-client -t =api'
}

@test "jump from the pinned window itself does nothing" {
  pinw red api @2 1000 vim
  printf '1000\t@2\tvim\n' | windows
  at red api @2
  run "$M" jump 1
  [ "$status" -eq 0 ]
  not_called 'switch-client'
  not_called 'select-window'
}

@test "a recreated session reuses window ids, so a stale stamp lands on the session" {
  # Ids restart after a kill-server: @2 exists again, but it is not the pinned window.
  pinw red api @2 1000 vim
  printf '2000\t@2\tsomething-else\n' | windows
  at red docs
  run "$M" jump 1
  called 'tmux switch-client -t =api'
  not_called 'select-window'
}

@test "a closed window lands on its session" {
  pinw red api @2 1000 vim
  printf '1000\t@1\tsh\n' | windows
  at red docs
  run "$M" jump 1
  called 'tmux switch-client -t =api'
  not_called 'select-window'
}

@test "a session pin on the same server is a switch-client, not a hop" {
  pinned red api red docs
  at red api
  run "$M" jump 2
  [ "$status" -eq 0 ]
  called 'tmux switch-client -t =docs'
  not_called 'detach-client'
}

@test "a window on another server: select it there, then replace this client with an attach" {
  pinw blue web @3 1000 vim
  printf '1000\t@3\tvim\n' | windows blue
  at red api
  run "$M" jump 1
  [ "$status" -eq 0 ]
  called 'tmux -L blue select-window -t =web:@3'
  called 'tmux detach-client -E exec env -u TMUX tmux -L blue attach-session -t =web'
  not_called 'switch-client'
}

@test "a session pin on another server attaches without selecting a window" {
  pinned red api blue web
  at red api
  run "$M" jump 2
  [ "$status" -eq 0 ]
  called 'tmux detach-client -E exec env -u TMUX tmux -L blue attach-session -t =web'
  not_called 'select-window'
}

@test "a slot on a socket path is reached with -S" {
  pinned /run/sockets/odd web
  at red api
  run "$M" jump 1
  called 'tmux -S /run/sockets/odd has-session -t =web'
  called 'tmux detach-client -E exec env -u TMUX tmux -S /run/sockets/odd attach-session -t =web'
}

@test "a session that is not running says so and detaches nothing" {
  pinned blue web
  printf 'other\n' > "$STUB_DIR/sessions.blue"
  at red api
  run "$M" jump 1
  [ "$status" -eq 0 ]
  shows "web is not running on blue"
  not_called 'detach-client'
}

@test "jump from outside tmux attaches, with no client to detach" {
  pinned blue web
  unset TMUX
  run "$M" jump 1
  [ "$status" -eq 0 ]
  called 'tmux -L blue attach-session -t =web'
  not_called 'detach-client'
}

@test "@muxpoon-goto takes a jump to another server, as session:window" {
  pinw blue web @3 1000 vim
  printf '1000\t@3\tvim\n' | windows blue
  hook my-hop
  at red api
  run "$M" jump 1
  [ "$status" -eq 0 ]
  called 'my-hop go blue web:@3'
  not_called 'detach-client'
}

@test "@muxpoon-goto takes a session that is not running, which it can wake" {
  pinned red api red docs
  printf 'api\n' > "$STUB_DIR/sessions"
  hook my-hop
  at red api
  run "$M" jump 2
  called 'my-hop go red docs'
  not_called 'switch-client'
}

@test "@muxpoon-goto not on PATH falls through to the plain hop" {
  pinned blue web
  printf 'no-such-command go\n' > "$STUB_DIR/opt.goto"
  at red api
  run "$M" jump 1
  [ "$status" -eq 0 ]
  called 'tmux detach-client -E exec env -u TMUX tmux -L blue attach-session -t =web'
}

@test "@muxpoon-goto stays off a same-server jump" {
  pinned red api red docs
  hook my-hop
  at red api
  run "$M" jump 2
  called 'tmux switch-client -t =docs'
  not_called 'my-hop'
}

@test "an empty slot says so and exits 0, so run-shell shows no error popup" {
  pinned red api
  at red api
  run "$M" jump 3
  [ "$status" -eq 0 ]
  shows "slot 3 is empty"
  not_called 'switch-client'
  not_called 'detach-client'
}

@test "a session pin to the session you are already in does nothing" {
  pinned red api
  at red api
  run "$M" jump 1
  [ "$status" -eq 0 ]
  not_called 'switch-client'
  not_called 'detach-client'
}

@test "blank lines left by the menu do not shift the slots" {
  mkdir -p "${LIST%/*}"
  printf 'red\tapi\n\n\nblue\tweb\n' > "$LIST"
  at red api
  run "$M" jump 2
  called 'tmux -L blue attach-session -t =web'
}

@test "ls shows the live window name, and says when a window has gone" {
  pinw red api @2 1000 old-name
  pinw red api @9 1000 closed
  printf '1000\t@2\tnew-name\n' | windows
  at red api @2
  run "$M" ls
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *'* 1  red      api:new-name'* ]]
  [[ "${lines[1]}" == *'api:closed  (window gone)'* ]]
}

@test "ls says when a session has gone" {
  pinned blue web
  printf 'other\n' > "$STUB_DIR/sessions.blue"
  at red api
  run "$M" ls
  says "web  (gone)"
}

@test "menu writes back what the editor saved, minus blanks and duplicates" {
  pinned red api blue web
  # An "editor" that reverses the list and adds a blank line and a duplicate.
  cat > "$BATS_TEST_TMPDIR/ed" <<'EOF'
#!/usr/bin/env bash
{ printf '\n'; tac "$1"; tail -1 "$1"; } > "$1.new" && mv "$1.new" "$1"
EOF
  chmod +x "$BATS_TEST_TMPDIR/ed"
  EDITOR="$BATS_TEST_TMPDIR/ed" run "$M" menu
  [ "$status" -eq 0 ]
  [ "$(cat "$LIST")" = "$(printf 'blue\tweb\nred\tapi')" ]
}

@test "menu in nvim maps Esc and q to save and close" {
  pinned red api
  mkdir -p "$BATS_TEST_TMPDIR/edbin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$@" > "%s/nvim.args"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/edbin/nvim"
  chmod +x "$BATS_TEST_TMPDIR/edbin/nvim"
  EDITOR="$BATS_TEST_TMPDIR/edbin/nvim" run "$M" menu
  [ "$status" -eq 0 ]
  run cat "$BATS_TEST_TMPDIR/nvim.args"
  says 'nnoremap <buffer> <Esc> <Cmd>wq<CR>'
  says 'nnoremap <buffer> q <Cmd>wq<CR>'
}

@test "the list path: MUXPOON_FILE, then @muxpoon-file, then the XDG default" {
  run "$M" file
  [ "$output" = "$XDG_STATE_HOME/muxpoon/slots" ]
  printf '~/pins\n' > "$STUB_DIR/opt.file"
  run "$M" file
  [ "$output" = "$HOME/pins" ]
  MUXPOON_FILE=/elsewhere/list run "$M" file
  [ "$output" = /elsewhere/list ]
}

@test "an unknown verb fails; no verb prints the usage" {
  run "$M" nonsense
  [ "$status" -eq 1 ]
  says "unknown verb: nonsense"
  run "$M"
  [ "$status" -eq 0 ]
  says "usage: muxpoon"
}

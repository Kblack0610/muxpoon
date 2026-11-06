#!/usr/bin/env bats
# muxpoon on real tmux servers, driven by real key presses through a real client. Skipped
# unless MUXPOON_REAL_TMUX=1, because it starts servers. Run it in CI or a container, not in
# a tmux session you care about. Every call names its server with -L or -S: $TMUX_TMPDIR
# does not isolate a server while $TMUX is set.
#
# The client under test is a pane of a third server, so it has a terminal with no pty
# helper, and `send-keys` to that pane is a person typing.

bats_require_minimum_version 1.5.0

setup() {
  [ -n "${MUXPOON_REAL_TMUX:-}" ] || skip "starts real tmux servers; set MUXPOON_REAL_TMUX=1"
  unset TMUX TMUX_PANE
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  LIST="$XDG_STATE_HOME/muxpoon/slots"
  A="mp-a-$$" B="mp-b-$$" O="mp-o-$$"
  # Short on purpose: a unix socket path is capped near 100 bytes.
  ODD_DIR="$(mktemp -d /tmp/mp.XXXXXX)"
  ODD="$ODD_DIR/odd"

  CONF="$BATS_TEST_TMPDIR/tmux.conf"
  cat > "$CONF" <<EOF
set -sg escape-time 0
run-shell "$ROOT/muxpoon.tmux"
EOF
  tmux -L "$A" -f "$CONF" new-session -d -s one -n first -x 100 -y 30
  tmux -L "$A" new-window -d -t one -n second
  tmux -L "$B" -f "$CONF" new-session -d -s two -n near -x 100 -y 30
  tmux -L "$B" new-window -d -t two -n far
  tmux -S "$ODD" -f "$CONF" new-session -d -s three -n odd -x 100 -y 30
  tmux -L "$O" -f /dev/null new-session -d -s outer -x 100 -y 30 "tmux -L $A attach-session -t one"
  tmux -L "$O" set -g escape-time 0
  settles at "$A" one:first
}

teardown() {
  [ -n "${MUXPOON_REAL_TMUX:-}" ] || return 0
  tmux -L "$O" kill-server 2>/dev/null || true
  tmux -L "$A" kill-server 2>/dev/null || true
  tmux -L "$B" kill-server 2>/dev/null || true
  tmux -S "$ODD" kill-server 2>/dev/null || true
  rm -rf "$ODD_DIR"
}

# settles <cmd> -- a client moves on its own time and nothing outside tmux can wait on that
# event, so this is the one sampling loop: 50 tries, 100ms apart.
settles() {
  local i
  for i in $(seq 1 50); do
    "$@" && return 0
    sleep 0.1
  done
  "$@"
}

# at <server> <session:window> -- the one client of that server sits there.
at() { [ "$(tmux -L "$1" list-clients -F '#{session_name}:#{window_name}' 2>/dev/null)" = "$2" ]; }

press() { tmux -L "$O" send-keys -t outer "$@"; }

pinned() { [ "$({ wc -l < "$LIST"; } 2>/dev/null | tr -d ' ')" = "$1" ]; }

odd_has_client() { [ -n "$(tmux -S "$ODD" list-clients 2>/dev/null)" ]; }

# slot_for <server> <window name> -- the slot line for a window of that server's only session.
slot_for() {
  tmux -L "$1" list-windows -a -F "$1"$'\t''#{session_name}'$'\t''#{window_id}'$'\t''#{session_created}'$'\t''#{window_name}' |
    awk -F'\t' -v w="$2" '$5 == w'
}

@test "the default keys are bound on a real server" {
  run tmux -L "$A" list-keys
  [[ "$output" == *"root"*"M-1"*"muxpoon jump 1"* ]]
  [[ "$output" == *"M-4"*"muxpoon jump 4"* ]]
  [[ "$output" == *"prefix"*"C-a"*"muxpoon toggle"* ]]
  [[ "$output" == *"prefix"*" e "*"display-popup -E"*"60%"*"80%"*"muxpoon menu"* ]]
}

@test "each bind carries its note, so list-keys -N says what it does" {
  run tmux -L "$A" list-keys -N
  [[ "$output" == *"M-1"*"muxpoon: jump to pinned slot 1, on any server"* ]]
  [[ "$output" == *"C-a"*"muxpoon: pin this window to the next slot; again unpins it"* ]]
  [[ "$output" == *" e "*"muxpoon: edit the pinned windows"* ]]
}

@test "Prefix+a pins this window, M-1 comes back to it, Prefix+a again unpins" {
  press C-b a
  settles pinned 1
  [ "$(cut -f5 "$LIST")" = first ]
  [ "$(cut -f1 "$LIST")" = "$A" ]

  tmux -L "$A" select-window -t one:second
  settles at "$A" one:second
  press M-1
  settles at "$A" one:first

  press C-b C-a
  settles pinned 0
}

@test "a pin leaves the pane as it was: run-shell output would open view mode over it" {
  press C-b a
  settles pinned 1
  press C-b a
  settles pinned 0
  [ "$(tmux -L "$A" display-message -p -t one '#{pane_in_mode}')" = 0 ]
}

@test "M-1 crosses to a window on another server, with nothing else installed" {
  mkdir -p "${LIST%/*}"
  slot_for "$B" far > "$LIST"
  press M-1
  settles at "$B" two:far
  run tmux -L "$A" list-clients
  [ -z "$output" ]
}

@test "a hop leaves the keys working on the far side, and back again" {
  mkdir -p "${LIST%/*}"
  { slot_for "$B" far; slot_for "$A" first; } > "$LIST"
  press M-1
  settles at "$B" two:far
  press M-2
  settles at "$A" one:first
}

@test "a server on an arbitrary socket is pinned by path and reached with -S" {
  mkdir -p "${LIST%/*}"
  printf '%s\tthree\n' "$ODD" > "$LIST"
  press M-1
  settles odd_has_client
  [ "$(tmux -S "$ODD" list-clients -F '#{session_name}')" = three ]
}

@test "@muxpoon-goto runs on a real jump" {
  mkdir -p "${LIST%/*}"
  slot_for "$B" far > "$LIST"
  printf '#!/bin/sh\necho "$@" > "%s/hook.args"\n' "$BATS_TEST_TMPDIR" > "$BATS_TEST_TMPDIR/my-hop"
  chmod +x "$BATS_TEST_TMPDIR/my-hop"
  tmux -L "$A" set -g @muxpoon-goto "$BATS_TEST_TMPDIR/my-hop"
  press M-1
  settles test -f "$BATS_TEST_TMPDIR/hook.args"
  [[ "$(cat "$BATS_TEST_TMPDIR/hook.args")" == "$B two:@"* ]]
  at "$A" one:first
}

@test "Prefix+e opens the list in a popup and the edit lands" {
  mkdir -p "${LIST%/*}"
  { slot_for "$A" first; slot_for "$A" second; } > "$LIST"
  cat > "$BATS_TEST_TMPDIR/ed" <<'EOF'
#!/bin/sh
sed -i 1d "$1"
EOF
  chmod +x "$BATS_TEST_TMPDIR/ed"
  tmux -L "$A" set-environment -g EDITOR "$BATS_TEST_TMPDIR/ed"
  press C-b e
  settles pinned 1
  [ "$(cut -f5 "$LIST")" = second ]
}

@test "@muxpoon-file moves the list" {
  tmux -L "$A" set -g @muxpoon-file "$BATS_TEST_TMPDIR/elsewhere/list"
  press C-b a
  settles test -s "$BATS_TEST_TMPDIR/elsewhere/list"
  [ ! -e "$LIST" ]
}

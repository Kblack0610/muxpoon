#!/usr/bin/env bats
# muxpoon.tmux against the recording tmux: which keys it binds for which options.

bats_require_minimum_version 1.5.0

setup() {
  load helper
  stub_init
  P="$ROOT/muxpoon.tmux"
}

set_opt() { printf '%s\n' "$2" > "$STUB_DIR/opt.$1"; }

@test "the defaults: a and C-a toggle, M-1 to M-4 jump, e opens the menu" {
  run "$P"
  [ "$status" -eq 0 ]
  called "tmux bind-key a run-shell $M toggle"
  called "tmux bind-key C-a run-shell $M toggle"
  called "tmux bind-key -n M-1 run-shell $M jump 1"
  called "tmux bind-key -n M-4 run-shell $M jump 4"
  not_called "M-5"
  called "tmux bind-key e display-popup -E -w 80% -h 60% $M menu"
}

@test "@muxpoon-slots sets how many jump keys are bound" {
  set_opt slots 6
  run "$P"
  called "tmux bind-key -n M-6 run-shell $M jump 6"
  not_called "M-7"
}

@test "a slot count that is not 1 to 9 is reported and the default stands" {
  set_opt slots 12
  run "$P"
  [ "$status" -eq 0 ]
  called "must be 1 to 9"
  called "M-4"
  not_called "M-5"
}

@test "every key option is honoured" {
  set_opt toggle-keys 'p C-p'
  set_opt menu-keys m
  set_opt jump-modifier C-
  set_opt popup-width 50%
  set_opt popup-height 40%
  run "$P"
  called "tmux bind-key p run-shell $M toggle"
  called "tmux bind-key C-p run-shell $M toggle"
  called "tmux bind-key m display-popup -E -w 50% -h 40% $M menu"
  called "tmux bind-key -n C-2 run-shell $M jump 2"
  not_called "bind-key a "
  not_called "M-1"
}

@test "none binds nothing for that option" {
  set_opt toggle-keys none
  set_opt menu-keys none
  set_opt jump-modifier none
  run "$P"
  [ "$status" -eq 0 ]
  not_called "bind-key"
}

@test "a checkout path with a space stays one word to the shell" {
  mkdir "$BATS_TEST_TMPDIR/a dir"
  cp "$P" "$M" "$BATS_TEST_TMPDIR/a dir/"
  run "$BATS_TEST_TMPDIR/a dir/muxpoon.tmux"
  called 'a\ dir/muxpoon toggle'
}

@test "a symlink to the entry still finds the script beside the real file" {
  mkdir "$BATS_TEST_TMPDIR/links"
  ln -s "$P" "$BATS_TEST_TMPDIR/links/muxpoon.tmux"
  run "$BATS_TEST_TMPDIR/links/muxpoon.tmux"
  called "tmux bind-key a run-shell $M toggle"
}

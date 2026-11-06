#!/usr/bin/env bash
# muxpoon.tmux - bind muxpoon's keys from its @muxpoon-* options. TPM runs this file; without
# TPM, run it from tmux.conf with run-shell, after the options are set. An option set to
# `none` binds nothing.

set -uf

printf -v bin '%q' "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/muxpoon"

# opt <name> <default> -- the option's value, or the default when unset, or nothing for `none`.
opt() {
  local v
  v="$(tmux show-option -gqv "@muxpoon-$1")"
  v="${v:-$2}"
  [ "$v" = none ] || printf '%s' "$v"
}

for key in $(opt toggle-keys 'a C-a'); do
  tmux bind-key -N "muxpoon: pin this window to the next slot; again unpins it" "$key" run-shell "$bin toggle"
done

for key in $(opt menu-keys e); do
  tmux bind-key -N "muxpoon: edit the pinned windows" "$key" display-popup -E -w "$(opt popup-width 80%)" -h "$(opt popup-height 60%)" "$bin menu"
done

modifier="$(opt jump-modifier M-)"
slots="$(opt slots 4)"
case "$slots" in
  [1-9]) ;;
  *)
    tmux display-message "muxpoon: @muxpoon-slots must be 1 to 9, not $slots"
    slots=4
    ;;
esac
if [ -n "$modifier" ]; then
  for n in $(seq 1 "$slots"); do
    tmux bind-key -N "muxpoon: jump to pinned slot $n, on any server" -n "$modifier$n" run-shell "$bin jump $n"
  done
fi

# Shared by the stub suites: a private state dir, the recording tmux on PATH, and the asserts.

stub_init() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  M="$ROOT/muxpoon"
  export STUB_DIR="$BATS_TEST_TMPDIR"
  export PATH="$ROOT/test/stub:$PATH"
  export XDG_STATE_HOME="$BATS_TEST_TMPDIR/state"
  export TMUX="/tmp/fake,1,0"
  unset MUXPOON_FILE TMUX_TMPDIR
  LIST="$XDG_STATE_HOME/muxpoon/slots"
}

called() {
  grep -qF -- "$1" "$STUB_DIR/calls.log" || {
    echo "not called: $1"
    cat "$STUB_DIR/calls.log"
    return 1
  }
}

not_called() {
  if grep -qF -- "$1" "$STUB_DIR/calls.log" 2>/dev/null; then
    echo "called: $1"
    return 1
  fi
}

# shows <text> -- the status line got this message.
shows() { called "display-message muxpoon: $1"; }

says() {
  [[ "$output" == *"$1"* ]] || {
    echo "output lacks: $1"
    echo "output was: $output"
    return 1
  }
}

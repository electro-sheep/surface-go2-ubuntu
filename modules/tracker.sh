# tracker: keep a history of which apps use the CPU, GPU, RAM and battery (usage-tracker).

step "Tracker: usage-tracker, recording in the background"
install -D -m 755 "$FILES/tracker/usage-tracker" ~/.local/bin/usage-tracker
if ~/.local/bin/usage-tracker service install >/dev/null; then
  ok "recording every 10 s (about 0.4% of one CPU core), keeping 14 days"
else
  warn "couldn't start it now; after logging in run: usage-tracker service install"
fi
info "See what used the CPU, RAM and battery: usage-tracker report (more in files/tracker/README.md)"

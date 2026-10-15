# tweaks: trims found with usage-tracker: Firefox's CPU decoding, disk writes and wakeups, a theme
# that floods the journal, and GNOME Software staying in RAM after an Activities search.

step "Tweaks: Firefox: no AV1, tabs saved every 60 s, no telemetry"
# AV1 is already off by policy (system module); user.js also slows the session saves (every 15 s
# by default) and turns off telemetry and studies (glean.dispatcher woke the CPU more than
# anything else). Ours go in a marked block at the top of the default profile's user.js; the
# user's own lines stay, below it, and win.
rc=0
msg=$(python3 -I "$FILES/tweaks/firefox-userjs.py" install "$FILES/tweaks/firefox-user.js") || rc=$?
if (( rc == 0 )); then
  while read -r line; do ok "$line"; done <<< "$msg"
  info "applies the next time Firefox starts"
elif (( rc == 2 )); then
  warn "Firefox has no profile yet: open it once, close it, then run ./install.sh tweaks"
else
  warn "couldn't update Firefox's user.js"
fi

step "Tweaks: adw-gtk3's GTK4 stylesheet off where GTK can't read it"
if [[ -n $(adw_gtk3_gtk4_unreadable) ]]; then
  adw_gtk3_gtk4_off
else
  ok "nothing to set aside (GTK4 $(dpkg-query -W -f '${Version}' libgtk-4-1 2>/dev/null || echo 'not installed'))"
fi

step "Tweaks: GNOME Software out of the Activities search"
# Typing in the Activities search starts every search provider, and GNOME Software then stays in
# memory (~250-310 MB). Installed apps still show up in the search; only the store's results go.
dis=$(gsettings get org.gnome.desktop.search-providers disabled)
if [[ $dis != *"'org.gnome.Software.desktop'"* ]]; then
  dis=$(python3 -I -c 'import ast,sys; l=list(ast.literal_eval(sys.argv[1].replace("@as ",""))); l.append("org.gnome.Software.desktop"); print(l)' "$dis")
  gsettings set org.gnome.desktop.search-providers disabled "$dis"
fi
ok "disabled search providers: $(gsettings get org.gnome.desktop.search-providers disabled)"
info "a GNOME Software already running in the background stays until you log out"

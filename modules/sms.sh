# sms: Chatty ("Chats") sends and receives texts through the SIM. The modem is data + SMS only
# ("no-voice"), so calls aren't possible. Chatty runs in the background from login (~70 MB RAM).

step "SMS: Chatty + MMS daemon"
apt_install chatty mmsd-tng
ok "open 'Chats' from the app grid; it stays running in the background for incoming texts"

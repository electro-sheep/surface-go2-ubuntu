// Surface Go 2 tuning: less CPU decoding, fewer disk writes and wakeups. Firefox reads these at
// every start.

// No AV1 hardware decoding on the UHD 615, so AV1 is decoded in software (dav1d).
// Sites fall back to VP9/H.264, which the GPU decodes.
user_pref("media.av1.enabled", false);

// GPU video decoding (VA-API, iHD from the snap's mesa-2404). On 26.04 Firefox left it off and
// decoded in software: its video process loaded libva but never opened the GPU (~0.5 core).
user_pref("media.ffmpeg.vaapi.enabled", true);
user_pref("media.hardware-video-decoding.force-enabled", true);

// Save the open tabs every 60 s instead of every 15 s (fewer disk writes and wakeups).
user_pref("browser.sessionstore.interval", 60000);

// Telemetry and studies off (glean.dispatcher was the most frequent waker on the machine).
user_pref("datareporting.healthreport.uploadEnabled", false);
user_pref("datareporting.policy.dataSubmissionEnabled", false);
user_pref("datareporting.usage.uploadEnabled", false);
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);
user_pref("toolkit.telemetry.archive.enabled", false);
user_pref("toolkit.telemetry.bhrPing.enabled", false);
user_pref("toolkit.telemetry.firstShutdownPing.enabled", false);
user_pref("toolkit.telemetry.newProfilePing.enabled", false);
user_pref("toolkit.telemetry.shutdownPingSender.enabled", false);
user_pref("toolkit.telemetry.updatePing.enabled", false);
user_pref("app.shield.optoutstudies.enabled", false);
user_pref("app.normandy.enabled", false);
user_pref("browser.newtabpage.activity-stream.feeds.telemetry", false);
user_pref("browser.newtabpage.activity-stream.telemetry", false);

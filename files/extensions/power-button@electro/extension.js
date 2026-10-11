import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as ShellDBus from 'resource:///org/gnome/shell/ui/shellDBus.js';
import * as LoginManager from 'resource:///org/gnome/shell/misc/loginManager.js';
import {Extension, InjectionManager} from 'resource:///org/gnome/shell/extensions/extension.js';

const POWER_KEYCODE = 124;                  // XF86PowerOff (evdev KEY_POWER + 8)
const JUST_WOKE_US = 1500 * 1000;           // a press this soon after the screen came on is the one that woke it
const BLANK_AFTER_IDLE_MS = 1500;           // button let go and the lock screen faded in
const CHECK_MUSIC_S = 60;
const SUSPEND_AFTER_QUIET_US = 5 * 60 * 1000 * 1000;
const IN_USE_MS = 60 * 1000;                // someone touched the lock screen this recently: don't suspend

const POWER_SAVE_ON = 0;
const POWER_SAVE_OFF = 3;
const INHIBIT_SUSPEND = 4;

// [bus name, object path, interface]
const DISPLAY_PROPS = ['org.gnome.Mutter.DisplayConfig', '/org/gnome/Mutter/DisplayConfig', 'org.freedesktop.DBus.Properties'];
const PROFILES = ['org.freedesktop.UPower.PowerProfiles', '/org/freedesktop/UPower/PowerProfiles', 'org.freedesktop.UPower.PowerProfiles'];
const SESSION = ['org.gnome.SessionManager', '/org/gnome/SessionManager', 'org.gnome.SessionManager'];
const MPRIS_PREFIX = 'org.mpris.MediaPlayer2.';

// The power button suspends, which stops music and drops Bluetooth headphones. Instead, like a
// phone: with music playing it locks and turns the screen off and the music carries on, with
// Power Saver held and idle suspend kept away until the screen is unlocked. Once the music has
// stopped for 5 minutes it suspends. With nothing playing the button suspends as before, and
// with the screen already off it only wakes it.
export default class PowerButtonExtension extends Extension {
    enable() {
        const ext = this;
        this._cancellable = new Gio.Cancellable();
        this._idle = global.backend.get_core_idle_monitor();
        this._lockSettings = new Gio.Settings({schema_id: 'org.gnome.desktop.screensaver'});
        this._screenOff = false;
        this._wokeAt = 0;
        this._musicMode = false;

        // GNOME Shell hands the power key to gnome-settings-daemon, which suspends. Keep that for
        // the cases above where it should, and handle the rest here.
        this._injections = new InjectionManager();
        this._injections.overrideMethod(ShellDBus.GnomeShell.prototype, '_emitAcceleratorActivated',
            original => function (action, device, timestamp) {
                const forward = () => original.call(this, action, device, timestamp);
                if (action === global.display.get_keybinding_action(POWER_KEYCODE, 0))
                    ext._onPowerKey(forward);
                else
                    forward();
            });

        global.backend.get_monitor_manager().connectObject('power-save-mode-changed',
            () => this._syncScreenOff(), this);
        Main.sessionMode.connectObject('updated', () => {
            if (!Main.sessionMode.isLocked)
                this._stopMusicMode();
        }, this);
        this._syncScreenOff();
    }

    disable() {
        this._injections.clear();
        this._injections = null;
        global.backend.get_monitor_manager().disconnectObject(this);
        Main.sessionMode.disconnectObject(this);
        this._stopMusicMode();
        this._removeWatch('_blankWatch');
        this._removeWatch('_wakeWatch');
        this._cancellable.cancel();
        this._cancellable = null;
        this._lockSettings = null;
        this._idle = null;
    }

    async _onPowerKey(forward) {
        try {
            // The key also counts as activity, so GNOME is already waking the screen.
            if (this._screenOff || GLib.get_monotonic_time() - this._wokeAt < JUST_WOKE_US)
                return;
            if (await this._musicPlaying())
                this._screenOffKeepPlaying();
            else
                forward();
        } catch (e) {
            logError(e, 'power-button');
            forward();
        }
    }

    _screenOffKeepPlaying() {
        if (!Main.sessionMode.isLocked) {
            // GNOME turns the screen off once the lock screen has faded in.
            if (this._lockSettings.get_boolean('lock-enabled'))
                Main.screenShield.lock(true);
            else
                Main.screenShield.activate(true);
        }
        if (Main.sessionMode.isLocked)
            this._startMusicMode();

        // It doesn't when the lock screen was already up, so once the button has been let go
        // (its release would wake the screen straight back up) do it here if it's still on.
        this._removeWatch('_blankWatch');
        this._blankWatch = this._idle.add_idle_watch(BLANK_AFTER_IDLE_MS, () => {
            this._removeWatch('_blankWatch');
            if (this._screenOff)
                return;
            this._setPowerSave(POWER_SAVE_OFF);
            this._removeWatch('_wakeWatch');
            this._wakeWatch = this._idle.add_user_active_watch(() => {
                this._wakeWatch = 0;
                this._setPowerSave(POWER_SAVE_ON);
            });
        });
    }

    _startMusicMode() {
        if (this._musicMode)
            return;
        this._musicMode = true;
        this._musicGen = (this._musicGen ?? 0) + 1;
        this._quietSince = 0;

        // power-profiles-daemon puts the previous profile back when the hold is released.
        this._acquire(Gio.DBus.system, PROFILES, 'HoldProfile',
            ['(sss)', ['power-saver', 'Music playing with the screen off', this.uuid]],
            cookie => (this._profileHold = cookie),
            cookie => this._send(Gio.DBus.system, PROFILES, 'ReleaseProfile', ['(u)', [cookie]]));
        this._acquire(Gio.DBus.session, SESSION, 'Inhibit',
            ['(susu)', [this.uuid, 0, 'Music playing with the screen off', INHIBIT_SUSPEND]],
            cookie => (this._suspendInhibit = cookie),
            cookie => this._send(Gio.DBus.session, SESSION, 'Uninhibit', ['(u)', [cookie]]));

        this._musicTimer = GLib.timeout_add_seconds(GLib.PRIORITY_LOW, CHECK_MUSIC_S, () => {
            this._checkMusic();
            return GLib.SOURCE_CONTINUE;
        });
    }

    _stopMusicMode() {
        if (!this._musicMode)
            return;
        this._musicMode = false;
        GLib.source_remove(this._musicTimer);
        this._musicTimer = 0;
        if (this._profileHold !== undefined)
            this._send(Gio.DBus.system, PROFILES, 'ReleaseProfile', ['(u)', [this._profileHold]]);
        if (this._suspendInhibit !== undefined)
            this._send(Gio.DBus.session, SESSION, 'Uninhibit', ['(u)', [this._suspendInhibit]]);
        this._profileHold = this._suspendInhibit = undefined;
    }

    async _checkMusic() {
        try {
            const playing = await this._musicPlaying();
            if (!this._musicMode)
                return;
            const now = GLib.get_monotonic_time();
            if (playing) {
                this._quietSince = 0;
                return;
            }
            this._quietSince ||= now;
            if (now - this._quietSince < SUSPEND_AFTER_QUIET_US || this._idle.get_idletime() < IN_USE_MS)
                return;
            this._stopMusicMode();
            LoginManager.getLoginManager().suspend();
        } catch (e) {
            logError(e, 'power-button');
        }
    }

    async _musicPlaying() {
        const bus = Gio.DBus.session;
        const [names] = (await bus.call('org.freedesktop.DBus', '/org/freedesktop/DBus',
            'org.freedesktop.DBus', 'ListNames', null, new GLib.VariantType('(as)'),
            Gio.DBusCallFlags.NONE, 1000, this._cancellable)).deepUnpack();
        // A player that doesn't answer in time counts as not playing.
        const states = await Promise.all(names.filter(n => n.startsWith(MPRIS_PREFIX)).map(name =>
            bus.call(name, '/org/mpris/MediaPlayer2', 'org.freedesktop.DBus.Properties', 'Get',
                new GLib.Variant('(ss)', ['org.mpris.MediaPlayer2.Player', 'PlaybackStatus']),
                new GLib.VariantType('(v)'), Gio.DBusCallFlags.NONE, 500, this._cancellable)
                .then(reply => reply.recursiveUnpack()[0], () => null)));
        return states.includes('Playing');
    }

    async _syncScreenOff() {
        try {
            const reply = await this._call(Gio.DBus.session, DISPLAY_PROPS, 'Get',
                ['(ss)', ['org.gnome.Mutter.DisplayConfig', 'PowerSaveMode']], this._cancellable);
            const off = reply.recursiveUnpack()[0] > POWER_SAVE_ON;
            if (this._screenOff && !off)
                this._wokeAt = GLib.get_monotonic_time();
            this._screenOff = off;
        } catch (e) {
            if (!e.matches(Gio.IOErrorEnum, Gio.IOErrorEnum.CANCELLED))
                logError(e, 'power-button');
        }
    }

    _setPowerSave(mode) {
        this._send(Gio.DBus.session, DISPLAY_PROPS, 'Set',
            ['(ssv)', ['org.gnome.Mutter.DisplayConfig', 'PowerSaveMode', new GLib.Variant('i', mode)]]);
    }

    // Takes a hold or inhibitor; if this music mode ended before the reply came, gives it straight back.
    async _acquire(bus, service, method, args, keep, release) {
        const gen = this._musicGen;
        try {
            const [cookie] = (await this._call(bus, service, method, args)).deepUnpack();
            if (this._musicMode && gen === this._musicGen)
                keep(cookie);
            else
                release(cookie);
        } catch (e) {
            logError(e, 'power-button');
        }
    }

    _call(bus, [name, path, iface], method, args, cancellable = null) {
        return bus.call(name, path, iface, method, new GLib.Variant(...args), null,
            Gio.DBusCallFlags.NONE, -1, cancellable);
    }

    _send(...args) {
        this._call(...args).catch(e => logError(e, 'power-button'));
    }

    _removeWatch(key) {
        if (this[key])
            this._idle.remove_watch(this[key]);
        this[key] = 0;
    }
}

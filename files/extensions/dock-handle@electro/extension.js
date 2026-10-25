import Clutter from 'gi://Clutter';
import GLib from 'gi://GLib';
import GObject from 'gi://GObject';
import Shell from 'gi://Shell';
import St from 'gi://St';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

// A home-bar pill at the bottom of the screen for the auto-hiding Ubuntu Dock. On a touchscreen
// there is no pointer to push against the edge, and a swipe up from the bottom edge opens the
// on-screen keyboard. So: tap the pill, or swipe up from it, and the dock slides up. A swipe
// from the rest of the bottom edge still opens the keyboard.

const DOCK_UUID = 'ubuntu-dock@ubuntu.com';
const SLOP = 40;          // logical px either side of the pill that still count as the pill
const SHOW_SECONDS = 5;   // a revealed dock hides again after this long untouched
const LIFT = 12;          // logical px the pill rises while you swipe it
// The keyboard swipe's own rule, from ui/keyboard.js
const OSK_MODES = Shell.ActionMode.ALL & ~Shell.ActionMode.LOCK_SCREEN;

export default class DockHandleExtension extends Extension {
    enable() {
        this._revealed = false;
        this._menuOpen = false;

        this._handle = new St.Button({
            style_class: 'dock-handle',
            can_focus: false,
            track_hover: false,
            child: new St.Widget({
                style_class: 'dock-handle-pill',
                x_align: Clutter.ActorAlign.CENTER,
                y_align: Clutter.ActorAlign.CENTER,
            }),
        });
        this._handle.connect('clicked', () => this._reveal());
        // The layout manager owns the chrome actor's visibility (it hides it in fullscreen), so
        // the pill sits in a container and we show and hide the pill.
        this._chrome = new St.Widget({layout_manager: new Clutter.BinLayout()});
        this._chrome.add_child(this._handle);
        Main.layoutManager.addTopChrome(this._chrome, {trackFullscreen: true});
        this._chrome.connect('notify::size', () => this._place());
        Main.layoutManager.connectObject('monitors-changed', () => this._place(), this);

        // Our swipe: the bottom edge, but only where the pill is.
        this._gesture = new Shell.EdgeDragGesture({name: 'Dock handle swipe', side: St.Side.BOTTOM});
        this._gesture.connect('may-recognize', g =>
            Main.actionMode === Shell.ActionMode.NORMAL && this._handleShown() && this._inZone(g));
        this._gesture.connect('progress', (_g, progress) => {
            this._handle.translation_y = -Math.min(progress, 1) * LIFT * this._scale();
        });
        this._gesture.connect('end', () => {
            this._handle.translation_y = 0;
            this._reveal();
        });
        this._gesture.connect('cancel', () => (this._handle.translation_y = 0));
        global.stage.add_action(this._gesture);

        // The keyboard's swipe: same rule as before, minus the pill's zone.
        this._oskGesture = Main.keyboard._bottomDragGesture ?? null;
        if (this._oskGesture) {
            GObject.signal_handlers_block_matched(this._oskGesture, {signalId: 'may-recognize'});
            this._oskId = this._oskGesture.connect('may-recognize', g =>
                Boolean(OSK_MODES & Main.actionMode) && !(this._handleShown() && this._inZone(g)));
        }

        Main.keyboard.connectObject('visibility-changed', () => this._sync(), this);
        Main.sessionMode.connectObject('updated', () => this._sync(), this);
        Main.overview.connectObject('showing', () => this._conceal(), this);
        global.display.connectObject('notify::focus-window', () => this._conceal(), this);

        // Ubuntu Dock may be enabled after us, or restarted: look for it again each time.
        this._dockManager = null;
        this._managerIds = [];
        this._findToken = 0;
        Main.extensionManager.connectObject('extension-state-changed', (_m, ext) => {
            if (ext.uuid === DOCK_UUID)
                this._findDock().catch(logError);
        }, this);
        this._findDock().catch(logError);
        this._place();
        this._sync();
    }

    disable() {
        this._findToken++;   // drop any lookup still waiting on its import
        this._conceal();
        this._dropDock();

        if (this._oskGesture) {
            this._oskGesture.disconnect(this._oskId);
            GObject.signal_handlers_unblock_matched(this._oskGesture, {signalId: 'may-recognize'});
            this._oskGesture = null;
        }
        global.stage.remove_action(this._gesture);
        this._gesture = null;

        for (const obj of [Main.layoutManager, Main.keyboard, Main.sessionMode, Main.overview,
            global.display, Main.extensionManager])
            obj.disconnectObject(this);
        this._chrome.destroy();
        this._chrome = this._handle = null;
    }

    // Ubuntu Dock's DockManager is a singleton in its docking.js; importing that module by the
    // same URI the dock loaded it from gives us the live one. Its docks are rebuilt whenever its
    // settings or the monitors change, so follow 'docks-ready'.
    async _findDock() {
        const token = ++this._findToken;
        this._dropDock();
        const dock = Main.extensionManager.lookup(DOCK_UUID);
        if (!dock)
            return;
        let DockManager;
        try {
            ({DockManager} = await import(`${dock.dir.get_uri()}/docking.js`));
        } catch (e) {
            logError(e, 'Dock Handle: can\'t load Ubuntu Dock');
            return;
        }
        const manager = DockManager.getDefault();
        if (token !== this._findToken || !manager)   // superseded or disabled meanwhile, or not running
            return;
        this._dockManager = manager;
        // DockManager has old-style signals (connect/disconnect only)
        this._managerIds = [
            manager.connect('docks-ready', () => this._watchDock()),
            manager.connect('docks-destroyed', () => this._unwatchDock()),
        ];
        this._watchDock();
    }

    _dropDock() {
        this._unwatchDock();
        for (const id of this._managerIds)
            this._dockManager?.disconnect(id);
        this._managerIds = [];
        this._dockManager = null;
        this._sync();
    }

    _dock() {
        return this._dockManager?.mainDock ?? null;
    }

    _watchDock() {
        this._unwatchDock();
        const dock = this._dock();
        if (!dock)
            return;
        this._watched = dock;
        dock._slider?.connectObject('notify::slide-x', () => this._sync(), this);
        dock.dash.connectObject(
            'menu-opened', () => {
                this._menuOpen = true;
                this._clearTimer();
            },
            'menu-closed', () => {
                this._menuOpen = false;
                if (this._revealed)
                    this._armTimer();
            }, this);
        this._sync();
    }

    _unwatchDock() {
        this._watched?._slider?.disconnectObject(this);
        this._watched?.dash?.disconnectObject(this);
        this._watched = null;
    }

    _scale() {
        return St.ThemeContext.get_for_stage(global.stage).scale_factor;
    }

    _place() {
        const monitor = Main.layoutManager.primaryMonitor;
        if (!monitor || !this._chrome)
            return;
        const [, natW] = this._chrome.get_preferred_width(-1);
        const [, natH] = this._chrome.get_preferred_height(natW);
        this._chrome.set_position(
            Math.round(monitor.x + (monitor.width - natW) / 2),
            monitor.y + monitor.height - natH);
    }

    // How far the dock has slid in: 0 hidden, 1 fully shown (no dock: treat as hidden).
    _dockShown() {
        return this._dock()?._slider?.slideX ?? 0;
    }

    _handleShown() {
        return this._chrome?.visible && this._handle.visible && this._handle.opacity > 0;
    }

    _sync() {
        if (!this._handle)
            return;
        const shown = this._dockShown();
        this._handle.opacity = Math.round((1 - shown) * 255);
        this._handle.visible = shown < 0.99 &&
            this._dock() !== null &&
            !Main.keyboard.visible &&
            !Main.sessionMode.isLocked && !Main.sessionMode.isGreeter;
    }

    _inZone(gesture) {
        const {x} = gesture.get_begin_centroid_abs();
        const [hx] = this._handle.get_transformed_position();
        const [hw] = this._handle.get_transformed_size();
        const slop = SLOP * this._scale();
        return x >= hx - slop && x <= hx + hw + slop;
    }

    _reveal() {
        const dock = this._dock();
        if (!dock || Main.overview.visible)
            return;
        // Ubuntu Dock keeps the dock up while its dash asks for it (it does the same itself for
        // urgent windows); we drop the request when you tap elsewhere, switch window or wait.
        dock.dash.requiresVisibility = true;
        this._revealed = true;
        this._armTimer();
        if (!this._capturedId) {
            this._capturedId = global.stage.connect('captured-event', (_a, event) => {
                const type = event.type();
                if (type === Clutter.EventType.TOUCH_BEGIN || type === Clutter.EventType.BUTTON_PRESS) {
                    const source = event.get_source();
                    if (this._dock()?.contains(source))
                        this._armTimer();
                    else if (!this._menuOpen && !this._handle.contains(source))   // a dock menu is its own actor
                        this._conceal();
                }
                return Clutter.EVENT_PROPAGATE;
            });
        }
    }

    _conceal() {
        if (!this._revealed)
            return;
        this._revealed = false;
        this._clearTimer();
        if (this._capturedId) {
            global.stage.disconnect(this._capturedId);
            this._capturedId = 0;
        }
        const dock = this._dock();
        if (dock)
            dock.dash.requiresVisibility = false;
    }

    _armTimer() {
        this._clearTimer();
        this._timerId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, SHOW_SECONDS, () => {
            this._timerId = 0;
            this._conceal();
            return GLib.SOURCE_REMOVE;
        });
    }

    _clearTimer() {
        if (this._timerId) {
            GLib.source_remove(this._timerId);
            this._timerId = 0;
        }
    }
}

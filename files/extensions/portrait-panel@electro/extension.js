import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import NM from 'gi://NM';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as NetworkStatus from 'resource:///org/gnome/shell/ui/status/network.js';
import {Extension, InjectionManager} from 'resource:///org/gnome/shell/extensions/extension.js';

// The top bar is too narrow in portrait, so drop the mobile data (4G) icon there and even out
// the icon spacing (see stylesheet.css) so the rest fit with room to breathe. Apps also open at
// sizes meant for landscape, so new app windows are maximised in portrait.
// Landscape keeps GNOME's normal behaviour and the user's settings.
export default class PortraitPanelExtension extends Extension {
    enable() {
        const ext = this;
        this._portrait = false;
        this._injections = new InjectionManager();

        this._injections.overrideMethod(NetworkStatus.Indicator.prototype, '_updateIcon',
            original => function () {
                original.call(this);
                const [dev] = this._mainConnection?.get_devices() ?? [];
                if (ext._portrait && dev?.device_type === NM.DeviceType.MODEM)
                    this._primaryIndicator.hide();
            });

        Main.layoutManager.connectObject('monitors-changed', () => this._sync(), this);
        global.display.connectObject('window-created', (_display, win) => this._maximizeNew(win), this);
        this._sync();
    }

    disable() {
        Main.layoutManager.disconnectObject(this);
        global.display.disconnectObject(this);
        this._injections.clear();
        this._injections = null;
        this._portrait = false;
        this._refresh();
    }

    _sync() {
        const monitor = Main.layoutManager.primaryMonitor;
        this._portrait = !!monitor && monitor.height > monitor.width;
        this._refresh();
    }

    _maximizeNew(win) {
        // Only ordinary, resizable app windows: not dialogs, splash screens or desktop icons.
        if (win.get_window_type() !== Meta.WindowType.NORMAL || win.get_transient_for() ||
            win.is_skip_taskbar() || !win.can_maximize())
            return;
        // Let the app finish setting up its window first, or its own initial size can win.
        global.compositor.get_laters().add(Meta.LaterType.BEFORE_REDRAW, () => {
            // Judge by the screen the window opened on, so a landscape external monitor
            // keeps normal behaviour while the tablet is in portrait.
            const monitor = win.get_monitor();
            if (monitor < 0 || !win.get_compositor_private())
                return GLib.SOURCE_REMOVE;
            const {width, height} = global.display.get_monitor_geometry(monitor);
            if (height > width && !win.is_fullscreen() &&
                win.get_maximized() !== Meta.MaximizeFlags.BOTH)
                win.maximize(Meta.MaximizeFlags.BOTH);
            return GLib.SOURCE_REMOVE;
        });
    }

    _refresh() {
        if (this._portrait)
            Main.panel.add_style_class_name('portrait-panel');
        else
            Main.panel.remove_style_class_name('portrait-panel');

        // The network indicator is created asynchronously; if it doesn't exist yet, its own
        // first _updateIcon() call will pick up the override.
        const {_network: network} = Main.panel.statusArea.quickSettings;
        if (network?._client)
            network._updateIcon();
    }
}

import NM from 'gi://NM';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as NetworkStatus from 'resource:///org/gnome/shell/ui/status/network.js';
import {Extension, InjectionManager} from 'resource:///org/gnome/shell/extensions/extension.js';

// The top bar is too narrow in portrait, so drop the mobile data (4G) icon there and even out
// the icon spacing (see stylesheet.css) so the rest fit with room to breathe.
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
        this._sync();
    }

    disable() {
        Main.layoutManager.disconnectObject(this);
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

import NM from 'gi://NM';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as NetworkStatus from 'resource:///org/gnome/shell/ui/status/network.js';
import * as SystemStatus from 'resource:///org/gnome/shell/ui/status/system.js';
import {Extension, InjectionManager} from 'resource:///org/gnome/shell/extensions/extension.js';

// The top bar is too narrow in portrait, so trade the mobile data (4G) icon for the battery
// percentage there. Landscape keeps GNOME's normal behaviour and the user's settings.
export default class PortraitPanelExtension extends Extension {
    enable() {
        const ext = this;
        this._portrait = false;
        this._injections = new InjectionManager();

        this._injections.overrideMethod(SystemStatus.Indicator.prototype, '_sync',
            original => function () {
                original.call(this);
                if (ext._portrait && this._systemItem.powerToggle.visible)
                    this._percentageLabel.show();
            });

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
        // Both indicators are created asynchronously; if they don't exist yet, their own
        // first _sync()/_updateIcon() call will pick up the overrides.
        const {_system: system, _network: network} = Main.panel.statusArea.quickSettings;
        system?._sync();
        if (network?._client)
            network._updateIcon();
    }
}

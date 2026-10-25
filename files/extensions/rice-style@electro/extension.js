import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

// Mostly CSS: GNOME Shell loads stylesheet.css while the extension is enabled. The code only moves
// the quick settings system row (battery, screenshot, settings, lock, power) below the sliders and
// tiles, like a phone's quick settings, and keeps it there as GNOME adds items later.
export default class RiceStyleExtension extends Extension {
    enable() {
        const qs = Main.panel.statusArea.quickSettings;
        this._grid = qs?.menu?._grid ?? null;
        if (!this._grid)
            return;
        this._system = () => qs._system?.quickSettingsItems?.[0] ?? null;
        this._grid.connectObject('child-added', () => this._toBottom(), this);
        this._toBottom();
    }

    disable() {
        if (!this._grid)
            return;
        this._grid.disconnectObject(this);
        // Back to GNOME's place for it: first after the layout's placeholder child.
        const item = this._system();
        if (item?.get_parent() === this._grid)
            this._grid.set_child_above_sibling(item, this._grid.get_first_child());
        this._grid = null;
    }

    _toBottom() {
        const item = this._system();
        if (item?.get_parent() === this._grid && this._grid.get_last_child() !== item)
            this._grid.set_child_above_sibling(item, null);
    }
}

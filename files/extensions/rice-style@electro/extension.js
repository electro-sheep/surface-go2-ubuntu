import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

// Nothing to do in code: GNOME Shell loads stylesheet.css while the extension is enabled.
export default class RiceStyleExtension extends Extension {
    enable() {}

    disable() {}
}

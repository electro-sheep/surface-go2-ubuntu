import GLib from 'gi://GLib';
import Meta from 'gi://Meta';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

// Never squeeze the notification column narrower than this (stage pixels).
const MIN_MESSAGE_LIST_WIDTH = 200;

/**
 * The clock drop-down (date menu) is a notification column plus a calendar
 * column. When it is wider than the monitor's work area, BoxPointer pins its
 * right edge to the screen and lets the left side hang off.
 *
 * While the menu is open, compare its laid-out width with the work area and
 * resize only the notification column: narrower when the menu overflows,
 * back to the theme's own width once there is room again (e.g. after
 * rotating to landscape). Works from real allocations rather than a one-off
 * measurement, because the menu's content keeps changing as it opens.
 */
export default class CalendarMenuFitExtension extends Extension {
    enable() {
        this._dateMenu = Main.panel.statusArea.dateMenu;
        this._messageList = this._dateMenu._messageList;
        this._boxPointer = this._dateMenu.menu.actor;
        this._naturalListWidth = 0;
        this._laterId = 0;

        this._dateMenu.menu.connectObject('open-state-changed',
            (_menu, isOpen) => isOpen && this._queueFit(), this);
        this._boxPointer.connectObject('notify::allocation',
            () => this._queueFit(), this);
    }

    disable() {
        if (this._laterId)
            global.compositor.get_laters().remove(this._laterId);
        this._laterId = 0;

        this._dateMenu.menu.disconnectObject(this);
        this._boxPointer.disconnectObject(this);
        this._messageList.set_width(-1);

        this._dateMenu = null;
        this._messageList = null;
        this._boxPointer = null;
    }

    _queueFit() {
        if (this._laterId)
            return;

        // Resizing from inside an allocation would re-enter layout, so do it
        // just before the next frame instead.
        this._laterId = global.compositor.get_laters().add(
            Meta.LaterType.BEFORE_REDRAW, () => {
                this._laterId = 0;
                this._fit();
                return GLib.SOURCE_REMOVE;
            });
    }

    _fit() {
        if (!this._dateMenu.menu.isOpen || !this._boxPointer.has_allocation())
            return;

        const listWidth = this._messageList.width;
        const isFixed = this._messageList.natural_width_set;
        // Without a fixed width the column is laid out at its natural width.
        if (!isFixed)
            this._naturalListWidth = listWidth;

        const monitorIndex = Main.layoutManager.findIndexForActor(this._dateMenu);
        const workArea = Main.layoutManager.getWorkAreaForMonitor(monitorIndex);
        // BoxPointer keeps this gap from each screen edge.
        const edgeGap = this._boxPointer.get_theme_node().get_length('-arrow-rise');
        const available = workArea.width - 2 * edgeGap;
        const otherWidth = this._boxPointer.width - listWidth;

        const target = Math.floor(Math.max(available - otherWidth, MIN_MESSAGE_LIST_WIDTH));
        if (target >= this._naturalListWidth) {
            if (isFixed)
                this._messageList.set_width(-1);
        } else if (Math.abs(target - listWidth) >= 1) {
            this._messageList.set_width(target);
        }
    }
}

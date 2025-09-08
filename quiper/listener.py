import json

from AppKit import (
    NSAlternateKeyMask,
    NSColor,
    NSCommandKeyMask,
    NSControlKeyMask,
    NSEvent,
    NSFont,
    NSKeyDownMask,
    NSMakeRect,
    NSShiftKeyMask,
    NSTextAlignmentCenter,
    NSTextField,
    NSView,
)

from .constants import DEFAULT_HOTKEY, LOG_DIR

HOTKEY_CONFIG_PATH = LOG_DIR / "hotkey_config.json"

SPECIAL_KEY_MAP = {
    49: "Space",
    36: "Return",
    53: "Escape",
    122: "F1",
    120: "F2",
    99: "F3",
    118: "F4",
    96: "F5",
    97: "F6",
    98: "F7",
    100: "F8",
    101: "F9",
    109: "F10",
    103: "F11",
    111: "F12",
    123: "Left Arrow",
    124: "Right Arrow",
    125: "Down Arrow",
    126: "Up Arrow",
}


def load_hotkey_config():
    if HOTKEY_CONFIG_PATH.exists():
        try:
            with open(HOTKEY_CONFIG_PATH, "r") as f:
                config = json.load(f)
                DEFAULT_HOTKEY.update(config)
        except (json.JSONDecodeError, KeyError):
            pass


def save_hotkey_config(hotkey):
    with open(HOTKEY_CONFIG_PATH, "w") as f:
        json.dump(hotkey, f)


def get_hotkey_display_string(event, flags, keycode):
    modifier_names = []
    if flags & NSShiftKeyMask:
        modifier_names.append("Shift")
    if flags & NSControlKeyMask:
        modifier_names.append("Control")
    if flags & NSAlternateKeyMask:
        modifier_names.append("Option")
    if flags & NSCommandKeyMask:
        modifier_names.append("Command")

    key_name = SPECIAL_KEY_MAP.get(
        keycode, NSEvent.eventWithCGEvent_(event).characters()
    )
    return " + ".join(modifier_names + [key_name]) if modifier_names else key_name


def set_hotkey_overlay(app):
    app.showWindow_(None)
    content_view = app.window.contentView()
    bounds = content_view.bounds()

    overlay = NSView.alloc().initWithFrame_(bounds)
    overlay.setWantsLayer_(True)
    overlay.layer().setBackgroundColor_(
        NSColor.colorWithWhite_alpha_(0.0, 0.5).CGColor()
    )

    container = NSView.alloc().initWithFrame_(
        NSMakeRect(
            (bounds.size.width - 400) / 2, (bounds.size.height - 180) / 2, 400, 180
        )
    )
    container.setWantsLayer_(True)
    container.layer().setBackgroundColor_(app.drag_area.layer().backgroundColor())
    container.layer().setCornerRadius_(10)

    message = NSTextField.alloc().initWithFrame_(NSMakeRect(0, 90, 400, 40))
    message.setStringValue_("Press the new hotkey combination.")
    message.setBezeled_(False)
    message.setDrawsBackground_(False)
    message.setEditable_(False)
    message.setSelectable_(False)
    message.setAlignment_(NSTextAlignmentCenter)
    message.setFont_(NSFont.boldSystemFontOfSize_(17))

    display_container = NSView.alloc().initWithFrame_(NSMakeRect(60, 40, 280, 38))
    display_container.setWantsLayer_(True)
    display_container.layer().setBackgroundColor_(NSColor.lightGrayColor().CGColor())
    display_container.layer().setCornerRadius_(5)

    display = NSTextField.alloc().initWithFrame_(NSMakeRect(0, -10, 280, 38))
    display.setStringValue_("Waiting for key press...")
    display.setBezeled_(False)
    display.setDrawsBackground_(False)
    display.setEditable_(False)
    display.setSelectable_(False)
    display.setAlignment_(NSTextAlignmentCenter)
    display.setFont_(NSFont.systemFontOfSize_(16))

    display_container.addSubview_(display)
    container.addSubview_(message)
    container.addSubview_(display_container)
    overlay.addSubview_(container)
    content_view.addSubview_(overlay)

    monitor = [None]

    def key_down_handler(event):
        flags = event.modifierFlags()
        keycode = event.keyCode()
        hotkey = {"flags": flags, "key": keycode}
        save_hotkey_config(hotkey)
        DEFAULT_HOTKEY.update(hotkey)
        display.setStringValue_(get_hotkey_display_string(event, flags, keycode))
        overlay.performSelector_withObject_afterDelay_("removeFromSuperview", None, 1.5)
        NSEvent.removeMonitor_(monitor[0])
        app.setup_global_hotkey_listener()

    monitor[0] = NSEvent.addLocalMonitorForEventsMatchingMask_handler_(
        NSKeyDownMask, key_down_handler
    )


def toggle_window_visibility(app):
    def listener():
        if app.window.isVisible():
            app.hideWindow_(None)
        else:
            app.showWindow_(None)
        return None

    return listener

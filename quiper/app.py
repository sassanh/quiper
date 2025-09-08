import os

import objc
from AppKit import (
    NSAlternateKeyMask,
    NSApp,
    NSApplicationActivationPolicyAccessory,
    NSBackingStoreBuffered,
    NSButton,
    NSButtonTypeMomentaryChange,
    NSColor,
    NSCommandKeyMask,
    NSControlKeyMask,
    NSEvent,
    NSEventMaskLeftMouseDown,
    NSFloatingWindowLevel,
    NSFontAttributeName,
    NSImage,
    NSImageOnly,
    NSMenu,
    NSMenuItem,
    NSNotificationCenter,
    NSResponder,
    NSSegmentedControl,
    NSShiftKeyMask,
    NSSquareStatusItemLength,
    NSStatusBar,
    NSView,
    NSViewHeightSizable,
    NSViewMinXMargin,
    NSViewMinYMargin,
    NSViewWidthSizable,
    NSWindow,
    NSWindowCollectionBehaviorFullScreenAuxiliary,
    NSWindowCollectionBehaviorMoveToActiveSpace,
    NSWindowCollectionBehaviorStationary,
    NSWindowDidResizeNotification,
    NSWindowStyleMaskBorderless,
    NSWindowStyleMaskResizable,
    NSWorkspace,
)
from Foundation import (
    NSURL,
    NSDate,
    NSKeyValueObservingOptionNew,
    NSMakeRect,
    NSMakeSize,
    NSURLRequest,
)
from Quartz import (
    CFRunLoopGetCurrent,
    CFRunLoopRemoveSource,
    CGEventTapEnable,
    kCFRunLoopCommonModes,
)
from quickmachotkey import mask, quickHotKey
from quickmachotkey.constants import VirtualKey, cmdKey, controlKey, optionKey, shiftKey
from WebKit import (
    WKNavigationActionPolicyAllow,
    WKNavigationActionPolicyCancel,
    WKNavigationTypeLinkActivated,
    WKWebsiteDataStore,
    WKWebView,
    WKWebViewConfiguration,
)

from .constants import (
    APP_NAME,
    DEFAULT_HOTKEY,
    DEFAULT_SERVICE,
    DRAGGABLE_AREA_HEIGHT,
    LOGO_PATH,
    STATUS_ITEM_OBSERVER_CONTEXT,
    UI_PADDING,
    WINDOW_CORNER_RADIUS,
    WINDOW_FRAME_AUTOSAVE_NAME,
)
from .launcher import install_startup, uninstall_startup
from .listener import load_hotkey_config, set_hotkey_overlay, toggle_window_visibility
from .settings import SettingsWindow, load_settings


class OverlayWindow(NSWindow):
    def canBecomeKeyWindow(self):
        return True

    def performKeyEquivalent_(self, event):
        if (
            event.modifierFlags() & NSCommandKeyMask
            and event.charactersIgnoringModifiers() == ","
        ):
            self.delegate().showSettings_(None)
            return True
        return objc.super(OverlayWindow, self).performKeyEquivalent_(event)

    def keyDown_(self, event):
        self.delegate().keyDown_(event)


class DraggableView(NSView):
    def initWithFrame_(self, frame):
        self_ = objc.super(DraggableView, self).initWithFrame_(frame)
        if self_:
            self_.setWantsLayer_(True)
            self_.setAutoresizingMask_(NSViewWidthSizable | NSViewMinYMargin)
            self_.updateBackgroundColor()
        return self_

    def viewDidChangeEffectiveAppearance(self):
        self.updateBackgroundColor()

    @objc.python_method
    def updateBackgroundColor(self):
        appearance = self.effectiveAppearance().name()
        if "Dark" in appearance:
            self.setBackgroundColor_(NSColor.colorWithCalibratedWhite_alpha_(0.2, 0.8))
        else:
            self.setBackgroundColor_(NSColor.colorWithCalibratedWhite_alpha_(0.9, 0.8))

    def setBackgroundColor_(self, color):
        if self.layer():
            self.layer().setBackgroundColor_(color.CGColor())

    def mouseDown_(self, event):
        self.window().performWindowDragWithEvent_(event)

    def mouse_down_can_drag_window(self, point):
        return self.hitTest_(point) == self


class AppController(NSResponder):
    webviews = objc.ivar()
    current_service = objc.ivar()
    active_indices = objc.ivar()
    drag_area = objc.ivar()
    service_selector = objc.ivar()
    session_selector = objc.ivar()
    status_item = objc.ivar()
    logo_light = objc.ivar()
    logo_dark = objc.ivar()
    window = objc.ivar()
    local_mouse_monitor = objc.ivar()
    event_tap = objc.ivar()
    run_loop_source = objc.ivar()
    inspector_visible = objc.ivar("Z")
    settings_window = objc.ivar()

    def applicationDidFinishLaunching_(self, notification):
        NSApp.setActivationPolicy_(NSApplicationActivationPolicyAccessory)

        self.initialize_state()
        self.create_main_window()
        self.create_views()
        self.setup_event_handling()
        self.hideWindow_(None)

    @objc.python_method
    def initialize_state(self):
        self.services = load_settings()
        self.current_service = DEFAULT_SERVICE
        self.active_indices = {service["name"]: 1 for service in self.services}
        self.webviews = {service["name"]: [] for service in self.services}
        self.inspector_visible = False

    @objc.python_method
    def create_main_window(self):
        self.window = (
            OverlayWindow.alloc().initWithContentRect_styleMask_backing_defer_(
                NSMakeRect(500, 200, 550, 620),
                NSWindowStyleMaskBorderless | NSWindowStyleMaskResizable,
                NSBackingStoreBuffered,
                False,
            )
        )
        self.window.setLevel_(NSFloatingWindowLevel)
        self.window.setCollectionBehavior_(
            NSWindowCollectionBehaviorMoveToActiveSpace
            | NSWindowCollectionBehaviorFullScreenAuxiliary
            | NSWindowCollectionBehaviorStationary
        )
        self.window.setFrameAutosaveName_(WINDOW_FRAME_AUTOSAVE_NAME)
        self.window.setOpaque_(False)
        self.window.setBackgroundColor_(NSColor.clearColor())
        self.window.setInitialFirstResponder_(self)

    @objc.python_method
    def create_views(self):
        content_view = NSView.alloc().initWithFrame_(
            self.window.contentRectForFrameRect_(self.window.frame())
        )
        content_view.setWantsLayer_(True)
        content_view.layer().setCornerRadius_(WINDOW_CORNER_RADIUS)
        content_view.layer().setBackgroundColor_(NSColor.whiteColor().CGColor())
        content_view.setAutoresizingMask_(NSViewWidthSizable | NSViewHeightSizable)
        self.window.setContentView_(content_view)

        self.updateContentBg()
        self.window.addObserver_forKeyPath_options_context_(
            self,
            "effectiveAppearance",
            NSKeyValueObservingOptionNew,
            STATUS_ITEM_OBSERVER_CONTEXT,
        )
        self.window.addObserver_forKeyPath_options_context_(
            self,
            "occlusionState",
            NSKeyValueObservingOptionNew,
            STATUS_ITEM_OBSERVER_CONTEXT,
        )

        self.create_drag_area(content_view)
        self.create_webviews(content_view)
        self.update_active_webview()

    @objc.python_method
    def create_drag_area(self, content_view):
        bounds = content_view.bounds()
        self.drag_area = DraggableView.alloc().initWithFrame_(
            NSMakeRect(
                0,
                bounds.size.height - DRAGGABLE_AREA_HEIGHT,
                bounds.size.width,
                DRAGGABLE_AREA_HEIGHT,
            )
        )
        content_view.addSubview_(self.drag_area)
        self.create_drag_area_buttons()

    @objc.python_method
    def create_drag_area_buttons(self):
        close_button = NSButton.alloc().initWithFrame_(
            NSMakeRect(UI_PADDING, UI_PADDING, 20, 20)
        )
        close_button.setImage_(
            NSImage.imageWithSystemSymbolName_accessibilityDescription_(
                "xmark.circle.fill", "Close"
            )
        )
        close_button.setBordered_(False)
        close_button.setButtonType_(NSButtonTypeMomentaryChange)
        close_button.setImagePosition_(NSImageOnly)
        close_button.setTarget_(self)
        close_button.setAction_(objc.selector(self.hideWindow_, signature=b"v@:@"))
        self.drag_area.addSubview_(close_button)

        self.service_selector = NSSegmentedControl.alloc().initWithFrame_(
            NSMakeRect(
                self.drag_area.bounds().size.width - 185,
                (self.drag_area.bounds().size.height - 25) / 2,
                180,
                25,
            )
        )
        self.service_selector.setAutoresizingMask_(NSViewMinXMargin | NSViewMinYMargin)
        self.service_selector.setSegmentCount_(len(self.services))
        self.service_selector.setSegmentStyle_(0)
        for i, service in enumerate(self.services):
            self.service_selector.setLabel_forSegment_(service["name"], i)
        services = [s["name"] for s in self.services]
        self.service_selector.setSelectedSegment_(
            services.index(self.current_service)
            if self.current_service in services
            else -1
        )
        self.service_selector.setTarget_(self)
        self.service_selector.setAction_(
            objc.selector(self.serviceChanged_, signature=b"v@:@")
        )
        self.drag_area.addSubview_(self.service_selector)

        self.create_session_selector()

    @objc.python_method
    def create_session_selector(self):
        service_selector_frame = self.service_selector.frame()
        selector_frame = NSMakeRect(
            service_selector_frame.origin.x - 300 - UI_PADDING,
            (self.drag_area.bounds().size.height - 25) / 2,
            300,
            25,
        )
        self.session_selector = NSSegmentedControl.alloc().initWithFrame_(
            selector_frame
        )
        self.session_selector.setAutoresizingMask_(NSViewMinXMargin | NSViewMinYMargin)
        self.session_selector.setSegmentCount_(10)
        self.session_selector.setSegmentStyle_(0)
        for i, session in enumerate([*range(1, 10), 0]):
            self.session_selector.setLabel_forSegment_(str(session), i)

        active_index = self.active_indices.get(self.current_service, -1)
        segment_index = active_index - 1 if active_index > 0 else active_index
        self.session_selector.setSelectedSegment_(segment_index)

        self.session_selector.setTarget_(self)
        self.session_selector.setAction_(
            objc.selector(self.sessionChanged_, signature=b"v@:@")
        )
        self.drag_area.addSubview_(self.session_selector)

        self.update_service_selector_width()

    @objc.python_method
    def switch_session(self, index):
        if self.active_indices.get(self.current_service, 1) != index:
            if self.inspector_visible:
                self.toggleInspector_(None)
            if self.current_service in self.active_indices:
                self.active_indices[self.current_service] = index
            self.update_active_webview()
            segment_index = index - 1 if index > 0 else -1
            self.session_selector.setSelectedSegment_(segment_index)
            if webview := self.get_current_webview():
                self.window.makeFirstResponder_(webview)

    @objc.IBAction
    def sessionChanged_(self, sender):
        selected_segment = sender.selectedSegment()
        index = selected_segment + 1 if selected_segment < 9 else 0
        self.switch_session(index)

    @objc.python_method
    def create_webviews(self, content_view):
        bounds = content_view.bounds()
        frame = NSMakeRect(
            0, 0, bounds.size.width, bounds.size.height - DRAGGABLE_AREA_HEIGHT
        )
        for service in self.services:
            for _ in range(len(self.webviews[service["name"]]), 10):
                config = WKWebViewConfiguration.alloc().init()
                config.preferences().setJavaScriptCanOpenWindowsAutomatically_(True)
                config.preferences().setValue_forKey_(True, "developerExtrasEnabled")
                webview = WKWebView.alloc().initWithFrame_configuration_(frame, config)
                webview.setAutoresizingMask_(NSViewWidthSizable | NSViewHeightSizable)
                webview.setUIDelegate_(self)
                webview.setNavigationDelegate_(self)
                webview.setCustomUserAgent_(
                    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
                )
                webview.setHidden_(True)
                self.webviews[service["name"]].append(webview)
                content_view.addSubview_(webview)

    @objc.python_method
    def setup_event_handling(self):
        self.window.setDelegate_(self)
        self.setup_status_bar()
        self.setup_global_hotkey_listener()
        NSNotificationCenter.defaultCenter().addObserver_selector_name_object_(
            self,
            objc.selector(self.windowDidResize_, signature=b"v@:@"),
            NSWindowDidResizeNotification,
            self.window,
        )

        self.local_mouse_monitor = (
            NSEvent.addLocalMonitorForEventsMatchingMask_handler_(
                NSEventMaskLeftMouseDown, self.handle_local_mouse_event
            )
        )

    def setup_status_bar(self):
        self.status_item = NSStatusBar.systemStatusBar().statusItemWithLength_(
            NSSquareStatusItemLength
        )
        button = self.status_item.button()
        if not button:
            return

        script_dir = os.path.dirname(os.path.abspath(__file__))
        self.logo_dark = NSImage.alloc().initWithContentsOfFile_(
            os.path.join(script_dir, LOGO_PATH)
        )
        self.logo_dark.setSize_(NSMakeSize(18, 18))
        self.logo_dark.setTemplate_(True)

        button.setImage_(self.logo_dark)

        menu = NSMenu.alloc().init()
        menu_items = [
            (f"Show {APP_NAME}", "showWindow:", ""),
            (f"Hide {APP_NAME}", "hideWindow:", "h"),
            ("---",),
            ("Settings", "showSettings:", ","),
            ("Show Inspector", "toggleInspector:", "i"),
            ("Clear Web Cache", "clearWebViewData:", ""),
            ("Set New Hotkey", "setHotkey:", ""),
            ("---",),
            ("Install at Login", "installAtLogin:", ""),
            ("Uninstall from Login", "uninstallFromLogin:", ""),
            ("---",),
            ("Quit", "terminate:", "q"),
        ]
        for item in menu_items:
            if item[0] == "---":
                menu.addItem_(NSMenuItem.separatorItem())
                continue
            title, action, key = item
            target = NSApp if action == "terminate:" else self
            selector = objc.selector(
                getattr(target, action.replace(":", "_")), signature=b"v@:@"
            )
            menu_item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
                title, selector, key
            )
            menu_item.setTarget_(target)
            menu.addItem_(menu_item)
        self.status_item.setMenu_(menu)

    def setup_global_hotkey_listener(self):
        load_hotkey_config()
        if hasattr(self, "hotkey") and self.hotkey:
            self.hotkey.unregister()

        flags = DEFAULT_HOTKEY["flags"]
        modifiers = []
        if flags & 0x10000:
            modifiers.append(cmdKey)
        if flags & 0x80000:
            modifiers.append(optionKey)
        if flags & 0x40000:
            modifiers.append(controlKey)
        if flags & 0x20000:
            modifiers.append(shiftKey)

        self.hotkey = quickHotKey(
            virtualKey=VirtualKey(DEFAULT_HOTKEY["key"]),
            modifierMask=mask(*modifiers),
        )(toggle_window_visibility(self))

    @objc.python_method
    def get_current_webview(self):
        if self.current_service not in self.webviews:
            return None
        return self.webviews[self.current_service][
            self.active_indices.get(self.current_service, 1)
        ]

    @objc.python_method
    def focus_input_in_active_webview(self):
        webview = self.get_current_webview()
        if not webview:
            return
        service = next(
            (s for s in self.services if s["name"] == self.current_service), None
        )
        if service and service.get("focus_selector"):
            webview.evaluateJavaScript_completionHandler_(
                f'setTimeout(() => document.querySelector("${service["focus_selector"]}")?.focus(), 0);',
                None,
            )

    @objc.python_method
    def update_active_webview(self):
        active_webview = self.get_current_webview()
        if not active_webview:
            return

        if active_webview.URL() is None:
            url = [
                s["url"] for s in self.services if s["name"] == self.current_service
            ][0]
            active_webview.loadRequest_(
                NSURLRequest.requestWithURL_(NSURL.URLWithString_(url))
            )

        for service, webviews in self.webviews.items():
            for i, webview in enumerate(webviews):
                webview.setHidden_(webview is not active_webview)
        if not active_webview.isHidden():
            self.focus_input_in_active_webview()

    @objc.IBAction
    def serviceChanged_(self, sender):
        if self.inspector_visible:
            self.toggleInspector_(None)
        self.current_service = (
            self.service_selector.labelForSegment_(
                self.service_selector.selectedSegment()
            )
            if self.service_selector.selectedSegment() >= 0
            else None
        )
        self.update_active_webview()
        active_index = self.active_indices.get(self.current_service, -1)
        segment_index = active_index - 1 if active_index > 0 else -1
        self.session_selector.setSelectedSegment_(segment_index)

    @objc.IBAction
    def showWindow_(self, sender):
        self.window.makeKeyAndOrderFront_(None)
        NSApp.activateIgnoringOtherApps_(True)
        if webview := self.get_current_webview():
            self.window.makeFirstResponder_(webview)
        self.focus_input_in_active_webview()

    @objc.IBAction
    def hideWindow_(self, sender):
        if self.settings_window and self.settings_window.isVisible():
            self.settings_window.hide()
        NSApp.hide_(None)

    @objc.python_method
    def keyDown_(self, event):
        modifiers = event.modifierFlags()
        key_code = event.keyCode()
        key_char = event.charactersIgnoringModifiers().lower()

        is_cmd = modifiers & NSCommandKeyMask
        is_option = modifiers & NSAlternateKeyMask
        is_control = modifiers & NSControlKeyMask
        is_shift = modifiers & NSShiftKeyMask

        if is_cmd:
            # Command + Control + Shift + Q to quit the app
            if is_control and is_shift:
                if key_char == "q":
                    NSApp.terminate_(None)
            elif is_control or is_option:
                try:
                    service_index = int(key_char) - 1
                    if 0 <= service_index < len(self.services):
                        self.current_service = self.services[service_index]["name"]
                        self.service_selector.setSelectedSegment_(service_index)
                        self.update_active_webview()
                        active_index = self.active_indices.get(self.current_service, -1)
                        segment_index = active_index - 1 if active_index > 0 else -1
                        self.session_selector.setSelectedSegment_(segment_index)
                except ValueError:
                    pass
                if key_char == "i":
                    self.toggleInspector_(None)

            # Command + 0-9 for instance switching
            else:
                # Key codes for 0-9 are 29, 18, 19, 20, 21, 23, 22, 26, 28, 25
                key_map = {
                    29: 0,
                    18: 1,
                    19: 2,
                    20: 3,
                    21: 4,
                    23: 5,
                    22: 6,
                    26: 7,
                    28: 8,
                    25: 9,
                }
                if key_code in key_map:
                    index = key_map[key_code]
                    self.switch_session(index)

                # Select all
                elif key_char == "a":
                    self.window.firstResponder().selectAll_(None)
                # Copy
                elif key_char == "c":
                    self.window.firstResponder().copy_(None)
                # Cut
                elif key_char == "x":
                    self.window.firstResponder().cut_(None)
                # Undo
                elif key_char == "z":
                    if (
                        hasattr(self.window.firstResponder(), "undoManager")
                        and self.window.firstResponder().undoManager().canUndo()
                    ):
                        self.window.firstResponder().undoManager().undo()
                # Redo
                elif key_char == "y":
                    if (
                        hasattr(self.window.firstResponder(), "undoManager")
                        and self.window.firstResponder().undoManager().canRedo()
                    ):
                        self.window.firstResponder().undoManager().redo()
                # Paste
                elif key_char == "v":
                    self.window.firstResponder().paste_(None)
                # Settings
                elif key_char == ",":
                    self.showSettings_(None)
                # Hide
                if key_char == "h":
                    self.hideWindow_(None)

    def windowDidResize_(self, notification):
        bounds = self.window.contentView().bounds()
        self.drag_area.setFrame_(
            NSMakeRect(
                0,
                bounds.size.height - DRAGGABLE_AREA_HEIGHT,
                bounds.size.width,
                DRAGGABLE_AREA_HEIGHT,
            )
        )
        webview_frame = NSMakeRect(
            0, 0, bounds.size.width, bounds.size.height - DRAGGABLE_AREA_HEIGHT
        )
        for webviews in self.webviews.values():
            for webview in webviews:
                webview.setFrame_(webview_frame)

        self.update_service_selector_width()

    def observeValueForKeyPath_ofObject_change_context_(
        self, keyPath, object, change, context
    ):
        if keyPath == "effectiveAppearance":
            self.updateContentBg()
        elif keyPath == "occlusionState":
            if (
                self.settings_window
                and self.settings_window.isVisible()
                and not self.window.isVisible()
            ):
                self.settings_window.hide()

    @objc.python_method
    def updateContentBg(self):
        is_dark = "Dark" in self.window.effectiveAppearance().name()
        content_view = self.window.contentView()
        if is_dark:
            content_view.layer().setBackgroundColor_(
                NSColor.colorWithCalibratedWhite_alpha_(0.1, 1.0).CGColor()
            )
        else:
            content_view.layer().setBackgroundColor_(NSColor.whiteColor().CGColor())

    @objc.IBAction
    def clearWebViewData_(self, sender):
        WKWebsiteDataStore.defaultDataStore().removeDataOfTypes_modifiedSince_completionHandler_(
            WKWebsiteDataStore.allWebsiteDataTypes(),
            NSDate.dateWithTimeIntervalSince1970_(0),
        )

    @objc.IBAction
    def installAtLogin_(self, sender):
        if install_startup():
            NSApp.terminate_(None)

    @objc.IBAction
    def uninstallFromLogin_(self, sender):
        uninstall_startup()

    @objc.IBAction
    def setHotkey_(self, sender):
        set_hotkey_overlay(self)

    def showSettings_(self, sender):
        if self.settings_window and self.settings_window.isVisible():
            self.settings_window.hide()
            return

        if not self.settings_window:
            self.settings_window = SettingsWindow.alloc().init()
            self.settings_window.setAppController_(self)
            self.settings_window.setDelegate_(self)

        self.settings_window.show()

    @objc.python_method
    def reload_services(self):
        # Remove old webviews from the content view to prevent accumulation
        content_view = self.window.contentView()

        self.services = load_settings()

        services = [s["name"] for s in self.services]
        for service, service_webviews in [*self.webviews.items()]:
            if service not in services:
                for webview in service_webviews:
                    if webview.superview() == content_view:
                        webview.removeFromSuperview()
                del self.webviews[service]
        for service in services:
            if service not in self.webviews:
                self.webviews[service] = []

        self.active_indices = {
            service["name"]: self.active_indices.get(service["name"], 1)
            for service in self.services
        }

        if len(self.services) != self.service_selector.segmentCount():
            self.service_selector.setSegmentCount_(len(self.services))

        for i, service in enumerate(self.services):
            self.service_selector.setLabel_forSegment_(service["name"], i)

        self.create_webviews(content_view)

        if self.current_service not in [s["name"] for s in self.services]:
            if len(self.services) > 0:
                self.current_service = self.services[0]["name"]
                self.service_selector.setSelectedSegment_(0)
            else:
                self.current_service = None
                self.service_selector.setSelectedSegment_(-1)

        self.serviceChanged_(None)

        self.update_active_webview()
        self.update_service_selector_width()

    @objc.IBAction
    def toggleInspector_(self, sender):
        webview = self.get_current_webview()
        if not webview:
            return
        inspector = webview._inspector()
        if self.inspector_visible:
            inspector.close()
            self.inspector_visible = False
        else:
            inspector.show()
            self.inspector_visible = True
        self.update_inspector_menu_item()

    @objc.python_method
    def update_inspector_menu_item(self):
        menu_item = self.status_item.menu().itemWithTitle_("Show Inspector")
        if not menu_item:
            menu_item = self.status_item.menu().itemWithTitle_("Hide Inspector")

        if self.inspector_visible:
            menu_item.setTitle_("Hide Inspector")
        else:
            menu_item.setTitle_("Show Inspector")

    @objc.python_method
    def update_service_selector_width(self):
        total_width = 0
        for i in range(self.service_selector.segmentCount()):
            label = self.service_selector.labelForSegment_(i)
            attributes = {NSFontAttributeName: self.service_selector.font()}
            size = label.sizeWithAttributes_(attributes)
            total_width += size.width + 20  # 20 for padding

        frame = self.service_selector.frame()
        frame.size.width = total_width
        frame.origin.x = self.drag_area.bounds().size.width - total_width - UI_PADDING
        self.service_selector.setFrame_(frame)

        session_frame = self.session_selector.frame()
        session_frame.origin.x = (
            self.service_selector.frame().origin.x
            - session_frame.size.width
            - UI_PADDING
        )
        self.session_selector.setFrame_(session_frame)

    @objc.python_method
    def handle_local_mouse_event(self, event):
        if event.window() == self.window:
            point_in_window = event.locationInWindow()
            point_in_drag_area = self.drag_area.convertPoint_fromView_(
                point_in_window, None
            )
            if self.drag_area.mouse_down_can_drag_window(point_in_drag_area):
                self.window.performWindowDragWithEvent_(event)
                return None
        return event

    def webView_decidePolicyForNavigationAction_decisionHandler_(
        self, webView, navigationAction, decisionHandler
    ):
        if navigationAction.navigationType() == WKNavigationTypeLinkActivated:
            url = navigationAction.request().URL()
            scheme = url.scheme().lower()
            if scheme in ["http", "https"]:
                NSWorkspace.sharedWorkspace().openURL_(url)
                decisionHandler(WKNavigationActionPolicyCancel)
                return

        decisionHandler(WKNavigationActionPolicyAllow)

    def windowWillClose_(self, notification):
        if notification.object() == self.settings_window:
            self.window.makeKeyAndOrderFront_(None)

    def applicationWillTerminate_(self, notification):
        if hasattr(self, "status_item") and self.status_item.button():
            self.status_item.button().removeObserver_forKeyPath_context_(
                self, "effectiveAppearance", STATUS_ITEM_OBSERVER_CONTEXT
            )
        if hasattr(self, "window") and self.window:
            self.window.removeObserver_forKeyPath_context_(
                self, "effectiveAppearance", STATUS_ITEM_OBSERVER_CONTEXT
            )

        NSNotificationCenter.defaultCenter().removeObserver_name_object_(
            self, NSWindowDidResizeNotification, self.window
        )
        if hasattr(self, "local_mouse_monitor"):
            NSEvent.removeMonitor_(self.local_mouse_monitor)
        if hasattr(self, "event_tap"):
            CGEventTapEnable(self.event_tap, False)
        if hasattr(self, "run_loop_source"):
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(), self.run_loop_source, kCFRunLoopCommonModes
            )

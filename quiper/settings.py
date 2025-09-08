import json
import os

import objc
from AppKit import (
    NSAlternateKeyMask,
    NSButton,
    NSColor,
    NSCommandKeyMask,
    NSControlKeyMask,
    NSDragOperationMove,
    NSDragOperationNone,
    NSFloatingWindowLevel,
    NSLayoutConstraint,
    NSMakeRect,
    NSMenu,
    NSMenuItem,
    NSObject,
    NSPopUpButton,
    NSScrollView,
    NSShiftKeyMask,
    NSStringPboardType,
    NSTableColumn,
    NSTableView,
    NSTableViewDropAbove,
    NSViewHeightSizable,
    NSViewWidthSizable,
    NSWindow,
    NSWindowCollectionBehaviorFullScreenAuxiliary,
    NSWindowCollectionBehaviorMoveToActiveSpace,
    NSWindowCollectionBehaviorStationary,
    NSWindowStyleMaskClosable,
    NSWindowStyleMaskResizable,
    NSWindowStyleMaskTitled,
)

SETTINGS_FILE = os.path.expanduser("~/Library/Application Support/Quiper/settings.json")

REFERRER = "https://github.io/sassanh/quiper"

ENGINES_TEMPLATES = {
    "Ollama - Open WebUI": {
        "url": "http://localhost:8080",
        "focus_selector": '[contenteditable="true"]\'',
    },
    "ChatGPT": {
        "url": f"https://chat.openai.com?referrer={REFERRER}",
        "focus_selector": "#prompt-textarea",
    },
    "Gemini": {
        "url": f"https://gemini.google.com?referrer={REFERRER}",
        "focus_selector": ".textarea",
    },
    "Grok": {
        "url": f"https://grok.com?referrer={REFERRER}",
        "focus_selector": 'textarea[aria-label="Ask Grok anything"],div[contenteditable=true]',
    },
    "Claude": {"url": f"https://claude.ai/?referrer={REFERRER}", "focus_selector": ""},
    "Perplexity": {
        "url": f"https://www.perplexity.ai/?referrer={REFERRER}",
        "focus_selector": "",
    },
}

DEFAULT_ENGINES = [
    {"name": name, **ENGINES_TEMPLATES["ChatGPT"]}
    for name in ["ChatGPT", "Gemini", "Grok"]
]


def load_settings():
    try:
        with open(SETTINGS_FILE, "r") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return DEFAULT_ENGINES


def save_settings(engines):
    os.makedirs(os.path.dirname(SETTINGS_FILE), exist_ok=True)
    with open(SETTINGS_FILE, "w") as f:
        json.dump(engines, f, indent=4)


class SettingsDataSource(NSObject):
    def init(self):
        self = objc.super(SettingsDataSource, self).init()
        if self:
            self.engines = load_settings()
        return self

    def numberOfRowsInTableView_(self, tableView):
        return len(self.engines)

    def tableView_objectValueForTableColumn_row_(self, tableView, tableColumn, row):
        identifier = tableColumn.identifier()
        return self.engines[row].get(identifier, "")

    def tableView_setObjectValue_forTableColumn_row_(
        self, tableView, obj, tableColumn, row
    ):
        identifier = tableColumn.identifier()
        self.engines[row][identifier] = obj
        self.save_settings()

    def tableView_writeRowsWithIndexes_toPasteboard_(
        self, tableView, rowIndexes, pasteboard
    ):
        # Encode the row indexes as a string for the pasteboard
        data = ",".join(str(i) for i in rowIndexes)
        pasteboard.declareTypes_owner_([NSStringPboardType], self)
        pasteboard.setString_forType_(data, NSStringPboardType)
        return True

    def tableView_validateDrop_proposedRow_proposedDropOperation_(
        self, tableView, info, row, operation
    ):
        # Only allow dropping between rows (not on)
        return (
            NSDragOperationMove
            if operation == NSTableViewDropAbove
            else NSDragOperationNone
        )

    def tableView_acceptDrop_row_dropOperation_(self, tableView, info, row, operation):
        pasteboard = info.draggingPasteboard()
        data = pasteboard.stringForType_(NSStringPboardType)
        if not data:
            return False
        indexes = [int(i) for i in data.split(",")]
        # Move the dragged rows to the new position
        for index in sorted(indexes, reverse=True):
            engine = self.engines.pop(index)
            insert_at = row if index >= row else row - 1
            self.engines.insert(insert_at, engine)
        tableView.reloadData()
        self.save_settings()
        return True

    def add_engine(self, tableView):
        self.engines.append(
            {"name": "New Engine", "url": "https://example.com", "focus_selector": ""}
        )
        tableView.reloadData()
        self.save_settings()

    def remove_engine(self, tableView):
        selected_row = tableView.selectedRow()
        if selected_row != -1:
            del self.engines[selected_row]
            tableView.reloadData()
            self.save_settings()

    def add_from_template(self, template_name):
        if template_name in ENGINES_TEMPLATES:
            template = ENGINES_TEMPLATES[template_name]
            self.engines.append(
                {
                    "name": template_name,
                    "url": template["url"],
                    "focus_selector": template["focus_selector"],
                }
            )
            self.table_view.reloadData()
            self.save_settings()

    def save_settings(self):
        os.makedirs(os.path.dirname(SETTINGS_FILE), exist_ok=True)
        with open(SETTINGS_FILE, "w") as f:
            json.dump(self.engines, f, indent=4)
        if hasattr(self, "app_controller") and self.app_controller:
            self.app_controller.reload_services()


class SettingsWindow(NSWindow):
    def canBecomeKeyWindow(self):
        return True

    def setAppController_(self, app_controller):
        self.app_controller = app_controller
        self.data_source.app_controller = app_controller
        self.data_source.table_view = self.table_view

    def init(self):
        self = objc.super(
            SettingsWindow, self
        ).initWithContentRect_styleMask_backing_defer_(
            NSMakeRect(0, 0, 800, 400),
            NSWindowStyleMaskTitled
            | NSWindowStyleMaskClosable
            | NSWindowStyleMaskResizable,
            2,
            False,
        )

        self.setLevel_(NSFloatingWindowLevel)
        self.setCollectionBehavior_(
            NSWindowCollectionBehaviorMoveToActiveSpace
            | NSWindowCollectionBehaviorFullScreenAuxiliary
            | NSWindowCollectionBehaviorStationary
        )
        self.setFrameAutosaveName_("SettingsWindow")
        self.setOpaque_(True)
        self.setBackgroundColor_(NSColor.windowBackgroundColor())

        self.setTitle_("Settings")
        self.center()

        content_view = self.contentView()

        self.scroll_view = NSScrollView.alloc().initWithFrame_(
            NSMakeRect(
                20,
                60,
                content_view.frame().size.width - 40,
                content_view.frame().size.height - 80,
            )
        )
        self.scroll_view.setAutoresizingMask_(NSViewWidthSizable | NSViewHeightSizable)
        self.scroll_view.setHasVerticalScroller_(True)

        self.table_view = NSTableView.alloc().initWithFrame_(content_view.bounds())
        self.table_view.registerForDraggedTypes_([NSStringPboardType])
        self.table_view.setDraggingSourceOperationMask_forLocal_(
            NSDragOperationMove, True
        )

        name_column = NSTableColumn.alloc().initWithIdentifier_("name")
        name_column.setTitle_("Name")
        name_column.setEditable_(True)
        name_column.setWidth_(150)
        self.table_view.addTableColumn_(name_column)

        url_column = NSTableColumn.alloc().initWithIdentifier_("url")
        url_column.setTitle_("URL")
        url_column.setEditable_(True)
        url_column.setWidth_(290)
        self.table_view.addTableColumn_(url_column)

        focus_selector_column = NSTableColumn.alloc().initWithIdentifier_(
            "focus_selector"
        )
        focus_selector_column.setTitle_("Focus Script")
        focus_selector_column.setEditable_(True)
        focus_selector_column.setWidth_(290)
        self.table_view.addTableColumn_(focus_selector_column)

        self.scroll_view.setDocumentView_(self.table_view)
        content_view.addSubview_(self.scroll_view)

        self.data_source = SettingsDataSource.alloc().init()
        self.table_view.setDataSource_(self.data_source)
        self.table_view.setDelegate_(self.data_source)

        self.create_buttons(content_view)
        return self

    def create_buttons(self, content_view):
        button_margin = 20
        button_height = 32
        add_button = NSButton.alloc().initWithFrame_(
            NSMakeRect(0, 0, 80, button_height)
        )
        add_button.setTitle_("Add")
        add_button.setBezelStyle_(1)
        add_button.setTarget_(self)
        add_button.setAction_(objc.selector(self.add_engine_, signature=b"v@:"))
        content_view.addSubview_(add_button)
        remove_button = NSButton.alloc().initWithFrame_(
            NSMakeRect(0, 0, 80, button_height)
        )
        remove_button.setTitle_("Remove")
        remove_button.setBezelStyle_(1)
        remove_button.setTarget_(self)
        remove_button.setAction_(objc.selector(self.remove_engine_, signature=b"v@:"))
        content_view.addSubview_(remove_button)
        self.add_from_template_button = NSPopUpButton.alloc().initWithFrame_(
            NSMakeRect(0, 0, 150, button_height)
        )
        self.add_from_template_button.setBezelStyle_(1)
        menu = NSMenu.alloc().init()
        menu.addItem_(
            NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
                "Add from Template", None, ""
            )
        )
        for template_name in ENGINES_TEMPLATES.keys():
            menu_item = NSMenuItem.alloc().initWithTitle_action_keyEquivalent_(
                template_name, None, ""
            )
            menu.addItem_(menu_item)
        self.add_from_template_button.setMenu_(menu)
        self.add_from_template_button.setTarget_(self)
        self.add_from_template_button.setAction_(
            objc.selector(self.addFromTemplate_, signature=b"v@:@")
        )
        content_view.addSubview_(self.add_from_template_button)

        add_button.setTranslatesAutoresizingMaskIntoConstraints_(False)
        remove_button.setTranslatesAutoresizingMaskIntoConstraints_(False)
        self.add_from_template_button.setTranslatesAutoresizingMaskIntoConstraints_(
            False
        )

        constraints = []
        # add_button constraints
        constraints.append(
            NSLayoutConstraint.constraintWithItem_attribute_relatedBy_toItem_attribute_multiplier_constant_(
                add_button, 5, 0, content_view, 5, 1.0, button_margin
            )
        )  # leading
        constraints.append(
            NSLayoutConstraint.constraintWithItem_attribute_relatedBy_toItem_attribute_multiplier_constant_(
                add_button, 4, 0, content_view, 4, 1.0, -button_margin
            )
        )  # bottom
        constraints.append(
            NSLayoutConstraint.constraintWithItem_attribute_relatedBy_toItem_attribute_multiplier_constant_(
                add_button, 7, 0, None, 0, 1.0, 80
            )
        )  # width
        constraints.append(
            NSLayoutConstraint.constraintWithItem_attribute_relatedBy_toItem_attribute_multiplier_constant_(
                add_button, 8, 0, None, 0, 1.0, button_height
            )
        )  # height
        # remove_button constraints
        constraints.append(
            NSLayoutConstraint.constraintWithItem_attribute_relatedBy_toItem_attribute_multiplier_constant_(
                remove_button, 5, 0, add_button, 6, 1.0, 10
            )
        )  # leading to add trailing +10
        constraints.append(
            NSLayoutConstraint.constraintWithItem_attribute_relatedBy_toItem_attribute_multiplier_constant_(
                remove_button, 4, 0, content_view, 4, 1.0, -button_margin
            )
        )  # bottom
        constraints.append(
            NSLayoutConstraint.constraintWithItem_attribute_relatedBy_toItem_attribute_multiplier_constant_(
                remove_button, 7, 0, None, 0, 1.0, 80
            )
        )  # width
        constraints.append(
            NSLayoutConstraint.constraintWithItem_attribute_relatedBy_toItem_attribute_multiplier_constant_(
                remove_button, 8, 0, None, 0, 1.0, button_height
            )
        )  # height
        # add_from_template_button constraints
        constraints.append(
            NSLayoutConstraint.constraintWithItem_attribute_relatedBy_toItem_attribute_multiplier_constant_(
                self.add_from_template_button, 5, 0, remove_button, 6, 1.0, 10
            )
        )  # leading to remove trailing +10
        constraints.append(
            NSLayoutConstraint.constraintWithItem_attribute_relatedBy_toItem_attribute_multiplier_constant_(
                self.add_from_template_button,
                4,
                0,
                content_view,
                4,
                1.0,
                -button_margin,
            )
        )  # bottom
        constraints.append(
            NSLayoutConstraint.constraintWithItem_attribute_relatedBy_toItem_attribute_multiplier_constant_(
                self.add_from_template_button, 7, 0, None, 0, 1.0, 150
            )
        )  # width
        constraints.append(
            NSLayoutConstraint.constraintWithItem_attribute_relatedBy_toItem_attribute_multiplier_constant_(
                self.add_from_template_button, 8, 0, None, 0, 1.0, button_height
            )
        )  # height

        content_view.addConstraints_(constraints)

    @objc.IBAction
    def addFromTemplate_(self, sender):
        template_name = sender.titleOfSelectedItem()
        if template_name != "Add from Template":
            self.data_source.add_from_template(template_name)
        self.add_from_template_button.selectItemAtIndex_(0)

    @objc.IBAction
    def add_engine_(self, sender):
        ...
        self.data_source.add_engine(self.table_view)

    @objc.IBAction
    def remove_engine_(self, sender):
        ...
        self.data_source.remove_engine(self.table_view)

    def hide(self):
        self.app_controller.window.makeKeyAndOrderFront_(None)
        self.setIsVisible_(False)

    def show(self):
        self.setIsVisible_(True)
        self.makeKeyAndOrderFront_(None)

    def keyDown_(self, event):
        key_char = event.charactersIgnoringModifiers().lower()
        modifiers = event.modifierFlags()

        is_cmd = modifiers & NSCommandKeyMask
        is_option = modifiers & NSAlternateKeyMask
        is_control = modifiers & NSControlKeyMask
        is_shift = modifiers & NSShiftKeyMask

        if event.keyCode() == 53:
            self.hide()
        elif is_cmd and not is_option and not is_control and not is_shift:
            if key_char == ",":
                self.hide()
            elif key_char == "a":
                self.firstResponder().selectAll_(None)
            # Copy
            elif key_char == "c":
                self.firstResponder().copy_(None)
            # Cut
            elif key_char == "x":
                self.firstResponder().cut_(None)
            # Undo
            elif key_char == "z":
                if (
                    hasattr(self.firstResponder(), "undoManager")
                    and self.firstResponder().undoManager().canUndo()
                ):
                    self.firstResponder().undoManager().undo()
            # Redo
            elif key_char == "y":
                if (
                    hasattr(self.firstResponder(), "undoManager")
                    and self.firstResponder().undoManager().canRedo()
                ):
                    self.firstResponder().undoManager().redo()
            # Paste
            elif key_char == "v":
                self.firstResponder().paste_(None)
            # Settings
            elif key_char == ",":
                self.hide()
            objc.super(SettingsDataSource, self).keyDown_(event)

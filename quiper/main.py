import argparse

from AppKit import NSApplication

from .app import AppController
from .launcher import install_startup, uninstall_startup


def main():
    parser = argparse.ArgumentParser(
        description="A multi-service web overlay application for macOS."
    )
    parser.add_argument(
        "--install", action="store_true", help="Install the app to run at login."
    )
    parser.add_argument(
        "--uninstall",
        action="store_true",
        help="Uninstall the app from running at login.",
    )
    args = parser.parse_args()

    if args.install:
        install_startup()
        return
    if args.uninstall:
        uninstall_startup()
        return

    app = NSApplication.sharedApplication()
    delegate = AppController.alloc().init()
    app.setDelegate_(delegate)
    app.run()


if __name__ == "__main__":
    main()

import getpass
import os
import plistlib
import sys
from pathlib import Path

from .constants import APP_NAME


def get_executable_path():
    if getattr(sys, "frozen", False):
        app_path = sys.argv[0]
        while not app_path.endswith(".app"):
            app_path = os.path.dirname(app_path)
        return os.path.join(
            app_path, "Contents", "MacOS", f"macos-{APP_NAME.lower()}-overlay"
        )
    else:
        return sys.executable


def get_program_arguments():
    if getattr(sys, "frozen", False):
        return [get_executable_path()]
    else:
        return [get_executable_path(), "-m", f"macos_{APP_NAME.lower()}_overlay"]


def install_startup():
    username = getpass.getuser()
    launch_agents_dir = Path.home() / "Library" / "LaunchAgents"
    launch_agents_dir.mkdir(parents=True, exist_ok=True)
    plist_path = (
        launch_agents_dir / f"com.{username}.{APP_NAME.lower().replace(' ', '-')}.plist"
    )

    plist = {
        "Label": f"com.{username}.{APP_NAME.lower().replace(' ', '-')}",
        "ProgramArguments": get_program_arguments(),
        "RunAtLoad": True,
        "KeepAlive": True,
    }

    with open(plist_path, "wb") as f:
        plistlib.dump(plist, f)

    os.system(f"launchctl load {plist_path}")
    print("Installed as startup app. To uninstall, run: quiper --uninstall")


def uninstall_startup():
    username = getpass.getuser()
    launch_agents_dir = Path.home() / "Library" / "LaunchAgents"
    plist_path = (
        launch_agents_dir / f"com.{username}.{APP_NAME.lower().replace(' ', '-')}.plist"
    )

    if plist_path.exists():
        os.system(f"launchctl unload {plist_path}")
        plist_path.unlink()
        print("Uninstalled startup app.")
    else:
        print("Startup app not found.")

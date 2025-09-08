# Quiper

A versatile macOS application that provides a system-wide overlay for multiple AI services, including Grok, Gemini ChatGPT and everything other engine that provides a web application. This tool allows you to quickly access your favorite AI assistants with a global hotkey, quickly switch between engines and manage multiple chat instances for each service.

![Quiper](https://quiper.sassanh.com/quiper-screenshot.jpg)

## Features

- **Multi-Service Support:** Seamlessly switch between Grok and Gemini.
- **Multi-Instance Chats:** Manage up to 10 simultaneous chat sessions for each service.
- **Global Hotkeys:**
  - `Option+Space` (customizable) to show/hide the application window.
  - `Command+Control+<digit-n>` to switch to nth engine.
  - `Cmd+0` through `Cmd+9` to switch between chat instances.
- **Customizable:**
  - Easily change the global hotkey to your preferred combination.
  - Adjust the window size and position to fit your workflow. It will remember the last position and size.
  - Add, remove, or reorder the AI services in the settings (`Cmd+,`).
  - Set css selectors for auto-focusing the input box of the chatbot.

## Installation

Easiest way to install and run the application is downloading it from the [Latest Release](
https://github.com/sassanh/quiper/releases/latest/) and put it in your Applications folder. macOS will nag you about it being from an unidentified developer, but you can bypass that by right-clicking the app and selecting "Open".

[Direct Download Link](https://github.com/sassanh/quiper/releases/latest/download/quiper.app.zip)

You can also install the application using pip:

```bash
python3 -m pip install quiper
```

Or you can clone the repository and run it directly:

```bash
git clone https://github.com/sassanh/quiper.git
cd quiper
uv run quiper
```

To build the application into a standalone macOS app, run:

```bash
uv run poe build-app
```

The dmg file will be created in the `dist` directory. You can then drag the app to your Applications folder.

To have the application launch automatically at login, run:

```bash
/Applications/quiper.app/Contents/MacOS/quiper --install
```

## How It Works

This application is built with PyObjC, which allows Python to interact with Apple's native Objective-C frameworks. It creates a borderless, always-on-top window that contains a `WKWebView` for each chat instance. The global hotkeys are registered using the `quickmachotkey` library, and the application state is managed in the `AppController` class.

## Contributing

This is an open-source project, and contributions are welcome. If you have ideas for new features or improvements, please open an issue or submit a pull request on the [GitHub repository](https://github.com/sassanh/quiper).

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Credits

It is greatly inspired by the [macos-grok-overlay](https://github.com/tchlux/macos-grok-overlay) project by [tchlux](https://github.com/tchlux), which was originally designed for the Grok AI service. The base of this codebase is mostly copied from that project, mostly the boilerplate code for setting up the macOS application.

Most of the code has been written with gemini-cli and grok. That's why it is so unorganized and messy :D If people find it useful, I will refactor it and make it cleaner, maybe even rewrite it in Swift.

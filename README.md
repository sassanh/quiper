# Quiper

A versatile macOS application that provides a system-wide overlay for multiple AI services, including Grok, Gemini ChatGPT and every other engine that provides a web application. This tool allows you to quickly access your favorite AI assistants with a global hotkey, quickly switch between engines and manage multiple chat instances for each service.

![Quiper](https://quiper.sassanh.com/quiper-screenshot.jpg)

## Features

- **Multi-Service Support:** Seamlessly switch between different AI services like Grok, Gemini, ChatGPT, and more.
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

These files are created in GitHub Actions and the whole build process and the resources used are transparent and open-source. You can verify the code in this repository. You can also ask a chatbot to verify the code and the build process for you :)

[Direct Download Link](https://github.com/sassanh/quiper/releases/latest/download/quiper.app.zip)

You can also clone the repository and run it directly:

```bash
git clone https://github.com/sassanh/quiper.git
cd quiper
swift run
```

To build the application into a standalone macOS app, run:

```bash
./build-app.sh
```

The app file will be created in the current directory. You can then drag the app to your Applications folder.

To have the application launch automatically at login, click on the app icon in the macOS status bar and select "Install at Login".

## How It Works

This application is a native swift application for macOS. It creates a borderless, always-on-top window that contains a `WKWebView` for each chat instance.

## Contributing

This is an open-source project, and contributions are welcome. If you have ideas for new features or improvements, please open an issue or submit a pull request on the [GitHub repository](https://github.com/sassanh/quiper).

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Credits

It is inspired by the [macos-grok-overlay](https://github.com/tchlux/macos-grok-overlay) project by [tchlux](https://github.com/tchlux), which was originally designed for the Grok AI service.

Most of the code has been written with gemini-cli, codex and grok.

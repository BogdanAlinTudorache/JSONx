# JSONx 🔧

JSONx is a lightweight, native macOS menu bar application written purely in Swift. It lives entirely in your Mac's status bar (with no dock icon!) and gives you instant access to JSON formatting, minification, validation, and side-by-side comparison — all without opening a browser or a heavy IDE.

## Features

* **Format & Pretty-Print** — Instantly beautify any JSON with configurable indentation (2 spaces, 4 spaces, or tabs).
* **Minify** — Collapse JSON to a single compact line for APIs and config files.
* **JSONC Support** — Strips `//` and `/* */` comments before parsing, so VS Code-style JSON with comments works out of the box.
* **Side-by-Side Comparison** — Paste two JSON blobs and get a recursive diff showing every added, removed, or changed key with full dot-path notation (e.g. `user.address.city`).
* **Sort Keys** — Optionally sort all object keys alphabetically on format.
* **Clipboard Integration** — One-click paste from clipboard and one-click copy of output.
* **Keyboard Shortcuts** — `⌘F` format, `⌘M` minify, `⌘K` clear all.
* **Persistent Tab Navigation** — Format, Compare, and Settings tabs always visible.
* **Theme Support** — System, Light, or Dark mode.
* **No Xcode Required** — Builds entirely from the terminal using a custom shell script.

## Requirements

* macOS 13.0 (Ventura) or later
* Swift 5.7+ (included with Xcode Command Line Tools)

## Preview

![JSONx preview](preview.png)

### Compare view

![JSONx compare](compare.png)

## Installation & Setup

You can build and run JSONx directly from your terminal without opening Xcode.

1. **Clone the repository:**
   ```bash
   git clone https://github.com/BogdanAlinTudorache/JSONx.git
   cd JSONx
   ```

2. **Make the build script executable (first time only):**
   ```bash
   chmod +x build.sh
   ```

3. **Build the app:**
   ```bash
   ./build.sh
   ```

4. **Run it directly:**
   ```bash
   open build/JSONx.app
   ```

5. **(Optional) Install to your Applications folder:**
   ```bash
   cp -r build/JSONx.app /Applications/
   ```

## Customization

Click the **JSONx** icon in your menu bar, then click the **Settings** tab to configure:

* **Indentation style** — 2 spaces, 4 spaces, or tab
* **Sort keys** — toggle alphabetical key sorting on format
* **Theme** — System / Light / Dark

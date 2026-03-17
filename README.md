# JSONx

A lightweight macOS menu bar app for JSON formatting, minification, and comparison.

## Features

- **Format JSON**: Pretty-print JSON with customizable indentation (2 spaces, 4 spaces, or tabs)
- **Minify JSON**: Compress JSON by removing whitespace
- **Compare JSON**: Side-by-side diff view for comparing two JSON documents
- **Sort Keys**: Alphabetically sort JSON object keys
- **Theme Support**: System, light, and dark mode support
- **Menu Bar Integration**: Quick access from your macOS menu bar

## Requirements

- macOS 10.15 (Catalina) or later
- Xcode Command Line Tools (for building from source)

## Installation

### Option 1: Build from Source

1. **Clone the repository**:
   ```bash
   git clone <your-repo-url>
   cd JSONx
   ```

2. **Make the build script executable**:
   ```bash
   chmod +x build.sh
   ```

3. **Run the build script**:
   ```bash
   ./build.sh
   ```

   The script will:
   - Generate the app icon
   - Compile the Swift source code
   - Create the app bundle
   - Install to `/Applications/JSONx.app`
   - Launch the app

### Option 2: Manual Build

If you prefer to build manually:

```bash
# Generate the icon
./generate_icon.sh

# Compile the app
swiftc -o JSONx main.swift -framework SwiftUI -framework AppKit

# Create app bundle structure
mkdir -p JSONx.app/Contents/MacOS
mkdir -p JSONx.app/Contents/Resources

# Move executable and resources
mv JSONx JSONx.app/Contents/MacOS/
cp iconset/icon.icns JSONx.app/Contents/Resources/

# Create Info.plist
cat > JSONx.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>JSONx</string>
    <key>CFBundleIconFile</key>
    <string>icon</string>
    <key>CFBundleIdentifier</key>
    <string>com.yourcompany.jsonx</string>
    <key>CFBundleName</key>
    <string>JSONx</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

# Install to Applications
cp -r JSONx.app /Applications/
open /Applications/JSONx.app
```

## Usage

1. **Launch the app**: Click the JSONx icon in your menu bar
2. **Format JSON**:
   - Paste or type JSON in the input area
   - Click "Format" to pretty-print
   - Click "Minify" to compress
   - Adjust indentation style in Settings
3. **Compare JSON**:
   - Switch to "Compare" mode
   - Paste JSON in both left and right panels
   - View differences highlighted in the output
4. **Settings**:
   - Choose indentation style (2 spaces, 4 spaces, or tabs)
   - Toggle "Sort Keys" option
   - Select theme (System, Light, or Dark)

## Development

### Project Structure

```
JSONx/
├── main.swift           # Main application code
├── build.sh            # Build and installation script
├── generate_icon.sh    # Icon generation script
├── iconset/            # App icon resources
└── build/              # Build output directory
```

### Building for Development

```bash
# Build without installing
./build.sh

# The app will be created in build/JSONx.app
```

## License

[Add your license here]

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

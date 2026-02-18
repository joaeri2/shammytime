# MCP Screenshot Server

A Model Context Protocol (MCP) server that enables Cursor agents to capture screenshots of application windows on macOS.

## Features

- **On-Demand Screenshot Capture**: Capture screenshots exactly when needed, not on a schedule
- **Window Discovery**: List and find windows by application name
- **Permission Checking**: Verify macOS permissions are granted
- **Multiple Output Formats**: PNG or JPG
- **Flexible Output**: Return as file path or base64-encoded data
- **Zero Background Resources**: No daemon, only runs when invoked

## Installation

### Prerequisites

- macOS 10.15+ (Catalina or later)
- Node.js 18+
- Screen Recording permission (macOS will prompt on first use)
- Accessibility permission (macOS will prompt on first use)

### Install Dependencies

```bash
cd mcp-screenshot-server
npm install
```

## Usage

### As MCP Server (with Cursor)

Add to your Cursor MCP configuration (`.cursor/mcp-config.json` or similar):

```json
{
  "mcpServers": {
    "screenshot": {
      "command": "node",
      "args": ["/path/to/mcp-screenshot-server/src/index.js"]
    }
  }
}
```

### Standalone Testing

You can test the server manually:

```bash
npm start
```

## Available Tools

### 1. `capture_window`

Capture a screenshot of a specific window.

**Parameters**:
- `window_name` (string, optional): Application name (e.g., "World of Warcraft")
- `window_id` (number, optional): Window ID (from `list_windows`)
- `format` (string, optional): Image format - "png" or "jpg" (default: "png")
- `return_base64` (boolean, optional): Return image as base64 string (default: false)

**Example**:
```javascript
{
  "window_name": "World of Warcraft",
  "format": "png",
  "return_base64": true
}
```

**Response**:
```json
{
  "success": true,
  "window_id": 12345,
  "window_name": "World of Warcraft",
  "timestamp": "2026-02-18T14:30:22Z",
  "format": "png",
  "image_data": "base64...",
  "size_bytes": 1234567
}
```

### 2. `list_windows`

List all available windows that can be captured.

**Parameters**:
- `application_name` (string, optional): Filter by application name
- `include_all_apps` (boolean, optional): Include all applications (default: true)

**Example**:
```javascript
{
  "application_name": "World of Warcraft"
}
```

**Response**:
```json
{
  "success": true,
  "count": 1,
  "windows": [
    {
      "id": 12345,
      "name": "World of Warcraft",
      "application": "World of Warcraft",
      "bounds": {
        "x": 0,
        "y": 0,
        "width": 1920,
        "height": 1080
      }
    }
  ]
}
```

### 3. `check_permissions`

Check if required macOS permissions are granted.

**Parameters**: None

**Response**:
```json
{
  "success": true,
  "all_granted": true,
  "permissions": {
    "screen_recording": {
      "granted": true,
      "required": true,
      "instructions": null
    },
    "accessibility": {
      "granted": true,
      "required": true,
      "instructions": null
    }
  }
}
```

## Example Agent Workflows

### Basic Screenshot

**Prompt**: "Show me my WoW screen"

**Agent Action**:
```javascript
const result = await mcp.invoke("capture_window", {
  window_name: "World of Warcraft",
  return_base64: true
});
```

### Find and Capture

**Prompt**: "What buffs do I have in WoW?"

**Agent Action**:
```javascript
// First, find the window
const windows = await mcp.invoke("list_windows", {
  application_name: "World of Warcraft"
});

if (windows.windows.length === 0) {
  return "World of Warcraft is not running";
}

// Capture the window
const screenshot = await mcp.invoke("capture_window", {
  window_id: windows.windows[0].id,
  return_base64: true
});

// Analyze the screenshot
// ...
```

### Permission Check

**Prompt**: "Check if screenshot permissions are set up"

**Agent Action**:
```javascript
const permissions = await mcp.invoke("check_permissions", {});

if (!permissions.all_granted) {
  return "Some permissions are missing. Please grant them in System Preferences.";
}
```

## Permissions Setup

### Screen Recording Permission

1. Open **System Preferences** → **Security & Privacy** → **Privacy**
2. Select **Screen Recording** from the left sidebar
3. Check the box next to your terminal application (e.g., Terminal, iTerm2)
4. Restart your terminal

### Accessibility Permission

1. Open **System Preferences** → **Security & Privacy** → **Privacy**
2. Select **Accessibility** from the left sidebar
3. Check the box next to your terminal application
4. Restart your terminal

You can verify permissions by running:

```bash
./scripts/check_permissions.sh all
```

## Troubleshooting

### "Application is not running"

The specified application is not currently running. Start the application and try again.

### "Permission denied"

Screen Recording or Accessibility permissions are not granted. Follow the permission setup instructions above.

### "Failed to capture window"

- Verify the window ID is correct using `list_windows`
- Ensure the application is not minimized (though it should work even when minimized)
- Check that the window still exists

### "No windows found"

The application is running but has no visible windows. Some applications may not expose their windows to AppleScript.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Cursor Agent                          │
└─────────────────────────────────────────────────────────┘
                            │
                            │ (MCP tool invocation)
                            ▼
┌─────────────────────────────────────────────────────────┐
│              MCP Screenshot Server                       │
│  - capture_window                                        │
│  - list_windows                                          │
│  - check_permissions                                     │
└─────────────────────────────────────────────────────────┘
                            │
                            │ (shell commands)
                            ▼
┌─────────────────────────────────────────────────────────┐
│              macOS Native Tools                          │
│  - screencapture (CLI)                                   │
│  - AppleScript (window discovery)                        │
└─────────────────────────────────────────────────────────┘
```

## Performance

- **Capture Time**: < 1 second per screenshot
- **Memory Usage**: < 50MB when idle
- **CPU Usage**: 0% when idle, < 5% during capture
- **File Size**: Typically 1-5MB per PNG screenshot

## Development

### Project Structure

```
mcp-screenshot-server/
├── package.json
├── src/
│   ├── index.js              # MCP server entry point
│   └── tools/
│       ├── capture.js        # capture_window tool
│       ├── list.js           # list_windows tool
│       ├── permissions.js    # check_permissions tool
│       └── utils.js          # Shared utilities
├── scripts/
│   ├── find_window.applescript
│   ├── list_windows.applescript
│   └── check_permissions.sh
└── README.md
```

### Running in Development

```bash
npm run dev
```

### Testing

Test individual scripts:

```bash
# List windows
osascript scripts/list_windows.applescript "World of Warcraft"

# Find window
osascript scripts/find_window.applescript "World of Warcraft"

# Check permissions
./scripts/check_permissions.sh all
```

## Comparison: MCP vs. Background Daemon

| Aspect | Background Daemon | MCP Tool (This) |
|--------|------------------|-----------------|
| Capture Trigger | Periodic (every 60s) | On-demand |
| Resource Usage | Continuous | Only when invoked |
| Latency | Up to 60s stale | Always fresh (< 1s) |
| Storage | Disk with rotation | Temp files or in-memory |
| Integration | File-based | Direct tool invocation |
| Maintenance | Daemon management | Simple server restart |

## Future Enhancements

- [ ] Windows support (using PowerShell)
- [ ] Linux support (using xdotool/wmctrl)
- [ ] OCR integration for text extraction
- [ ] Image compression options
- [ ] Region-based capture (crop to specific area)
- [ ] Multi-window capture (combine multiple windows)
- [ ] Video recording support

## License

MIT License - See LICENSE file for details

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## Credits

Part of the ShammyTime project for World of Warcraft automation.

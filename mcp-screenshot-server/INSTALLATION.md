# Installation Guide

## Overview

The MCP Screenshot Server is a **standalone tool** that should be installed **outside** any specific project directory. This allows you to use it globally with Cursor across all your projects.

---

## Why Install Separately?

✅ **Universal Tool**: Capture screenshots from any application, not just WoW  
✅ **Multiple Projects**: Use in all your Cursor projects  
✅ **Clean Separation**: Keep tools separate from project code  
✅ **Easy Updates**: Update the tool without affecting projects  

---

## Installation Steps

### 1. Choose Installation Location

**Recommended**: `~/mcp-screenshot-server` (your home directory)

This keeps it:
- Out of project directories
- Easy to find and update
- Accessible from anywhere

### 2. Copy or Clone

#### Option A: Copy from ShammyTime (if you found it there)

```bash
# Copy the entire directory to your home folder
cp -r /path/to/shammytime/mcp-screenshot-server ~/mcp-screenshot-server
```

#### Option B: Clone from Repository (if separate repo exists)

```bash
# Clone to permanent location
git clone <repository-url> ~/mcp-screenshot-server
```

#### Option C: Download Release

```bash
# Download and extract to ~/mcp-screenshot-server
# Then:
cd ~/mcp-screenshot-server
```

### 3. Install Dependencies

```bash
cd ~/mcp-screenshot-server
npm install
```

This will install:
- `@modelcontextprotocol/sdk` - MCP server framework
- `execa` - Shell command execution

### 4. Verify Installation

```bash
# Check permissions
./scripts/check_permissions.sh all

# Test window discovery
osascript scripts/find_window.applescript "Finder"

# Test list windows
osascript scripts/list_windows.applescript
```

---

## Configure Cursor

### Global Configuration (Recommended)

Add to your **global** Cursor MCP configuration:

**File Location**:
- **macOS/Linux**: `~/.cursor/mcp-config.json`
- **Windows**: `%APPDATA%\.cursor\mcp-config.json`

**Or via Cursor UI**:
1. Open Cursor Settings
2. Go to Features → MCP Servers
3. Add new server configuration

**Configuration**:
```json
{
  "mcpServers": {
    "screenshot": {
      "command": "node",
      "args": ["/Users/YOUR_USERNAME/mcp-screenshot-server/src/index.js"],
      "env": {}
    }
  }
}
```

**Important**: Replace `/Users/YOUR_USERNAME/` with your actual home directory path.

**To find your home directory**:
```bash
# macOS/Linux
echo $HOME

# Windows PowerShell
echo $env:USERPROFILE
```

### Example Paths

**macOS**:
```json
"/Users/john/mcp-screenshot-server/src/index.js"
```

**Linux**:
```json
"/home/john/mcp-screenshot-server/src/index.js"
```

**Windows**:
```json
"C:\\Users\\john\\mcp-screenshot-server\\src\\index.js"
```

---

## Grant Permissions

### macOS Permissions Required

1. **Screen Recording**
   - Open **System Preferences** → **Security & Privacy** → **Privacy**
   - Select **Screen Recording** from left sidebar
   - Click the lock to make changes
   - Add and enable your **terminal application** (Terminal, iTerm2, etc.)

2. **Accessibility**
   - Same location: **System Preferences** → **Security & Privacy** → **Privacy**
   - Select **Accessibility** from left sidebar
   - Add and enable your **terminal application**

3. **Restart Terminal**
   - Close and reopen your terminal after granting permissions

### Verify Permissions

```bash
cd ~/mcp-screenshot-server
./scripts/check_permissions.sh all
```

Expected output:
```
✓ Screen Recording: Granted
✓ Accessibility: Granted

All permissions granted!
```

---

## Test the Installation

### 1. Restart Cursor

After configuring, restart Cursor to load the MCP server.

### 2. Test with Agent

Open any project in Cursor and try these prompts:

**Check Setup**:
```
Use the check_permissions tool to verify screenshot setup
```

**List Windows**:
```
Use the list_windows tool to show all available windows
```

**Capture Screenshot** (with any app running):
```
Use the capture_window tool to take a screenshot of Finder
```

### 3. Expected Results

If working correctly:
- Agent will invoke the tool
- You'll see tool output in the response
- Screenshots will be captured successfully

---

## Troubleshooting

### "MCP server not found"

**Problem**: Cursor can't find the server

**Solutions**:
1. Verify the path in your config is **absolute** (starts with `/` or `C:\`)
2. Check the path exists: `ls ~/mcp-screenshot-server/src/index.js`
3. Ensure `node` is in your PATH: `which node`
4. Restart Cursor after configuration changes

### "Permission denied" errors

**Problem**: macOS permissions not granted

**Solutions**:
1. Run `./scripts/check_permissions.sh all`
2. Grant missing permissions in System Preferences
3. **Restart your terminal** after granting
4. Restart Cursor

### "Application not running"

**Problem**: Trying to capture a window that doesn't exist

**Solutions**:
1. Start the application first
2. Use `list_windows` to see available windows
3. Check exact application name (case-sensitive)

### Server crashes or hangs

**Problem**: MCP server becomes unresponsive

**Solutions**:
1. Check Cursor logs for error messages
2. Try running manually: `node ~/mcp-screenshot-server/src/index.js`
3. Verify Node.js version: `node --version` (need 18+)
4. Reinstall dependencies: `cd ~/mcp-screenshot-server && npm install`
5. Restart Cursor

---

## Directory Structure

After installation, you should have:

```
~/mcp-screenshot-server/
├── package.json              # Dependencies
├── package-lock.json         # Lock file
├── node_modules/             # Installed packages
├── src/
│   ├── index.js             # MCP server entry point
│   └── tools/
│       ├── capture.js       # capture_window tool
│       ├── list.js          # list_windows tool
│       ├── permissions.js   # check_permissions tool
│       └── utils.js         # Shared utilities
├── scripts/
│   ├── find_window.applescript
│   ├── list_windows.applescript
│   └── check_permissions.sh
├── README.md                # Main documentation
├── CURSOR_SETUP.md          # Setup guide
└── INSTALLATION.md          # This file
```

---

## Updating

To update the MCP server:

```bash
cd ~/mcp-screenshot-server

# If installed via git
git pull
npm install

# If copied manually
# Copy new version over existing directory
# Then:
npm install
```

Restart Cursor after updating.

---

## Uninstalling

To remove the MCP server:

1. **Remove from Cursor configuration**:
   - Edit `~/.cursor/mcp-config.json`
   - Remove the `"screenshot"` entry
   - Restart Cursor

2. **Delete installation**:
   ```bash
   rm -rf ~/mcp-screenshot-server
   ```

---

## Using with Multiple Applications

Once installed globally, you can use the screenshot tool with **any** application:

**World of Warcraft**:
```
Capture a screenshot of World of Warcraft
```

**Discord**:
```
Capture a screenshot of Discord
```

**VS Code**:
```
Capture a screenshot of Visual Studio Code
```

**Any Application**:
```
List all windows, then capture the Chrome window
```

---

## Next Steps

1. ✅ Installation complete
2. ✅ Permissions granted
3. ✅ Cursor configured
4. ✅ Tested successfully

Now you can:
- Use in any Cursor project
- Capture any application window
- Integrate with your workflows

See **README.md** for full documentation and **CURSOR_SETUP.md** for advanced configuration.

---

## Support

If you encounter issues:

1. Check **CURSOR_SETUP.md** for detailed troubleshooting
2. Run `./scripts/check_permissions.sh all` to diagnose
3. Review Cursor logs for error messages
4. Verify Node.js version: `node --version` (need 18+)

---

**Installation Location**: `~/mcp-screenshot-server` (recommended)  
**Configuration Location**: `~/.cursor/mcp-config.json` (global)  
**Permissions**: System Preferences → Security & Privacy → Privacy

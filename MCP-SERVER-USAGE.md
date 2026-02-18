# MCP Screenshot Server - Usage Guide

## Quick Reference

The MCP Screenshot Server is a **standalone tool** that lives **outside** this project.

---

## Installation (One-Time Setup)

### 1. Copy to Standalone Location

```bash
# From this project directory
cp -r mcp-screenshot-server ~/mcp-screenshot-server
cd ~/mcp-screenshot-server
npm install
```

### 2. Grant macOS Permissions

```bash
./scripts/check_permissions.sh all
```

Then grant in **System Preferences** → **Security & Privacy** → **Privacy**:
- ✅ Screen Recording
- ✅ Accessibility

### 3. Configure Cursor Globally

Create or edit `~/.cursor/mcp-config.json`:

```json
{
  "mcpServers": {
    "screenshot": {
      "command": "node",
      "args": ["/Users/YOUR_USERNAME/mcp-screenshot-server/src/index.js"]
    }
  }
}
```

**Replace `/Users/YOUR_USERNAME/` with your actual home directory.**

To find it: `echo $HOME`

### 4. Restart Cursor

Close and reopen Cursor to load the MCP server.

---

## Usage Examples

Once configured, use these prompts in **any** Cursor project:

### Basic Screenshot

```
Take a screenshot of World of Warcraft
```

### List Available Windows

```
Show me all windows I can capture
```

### Check Setup

```
Verify that screenshot permissions are configured
```

### Analyze Game State

```
Take a screenshot of WoW and tell me what buffs I have
```

### Capture Any Application

```
Capture a screenshot of Discord
Capture a screenshot of Chrome
Capture a screenshot of VS Code
```

---

## Why Standalone?

✅ **Universal**: Works in all Cursor projects, not just ShammyTime  
✅ **Any App**: Capture any application window, not just WoW  
✅ **Single Install**: Install once, use everywhere  
✅ **Easy Updates**: Update in one place  
✅ **Clean Architecture**: Tools separate from projects  

---

## Documentation

Full documentation in `mcp-screenshot-server/`:

- **INSTALLATION.md** - Detailed installation guide
- **README.md** - Technical documentation
- **CURSOR_SETUP.md** - Cursor configuration
- **README-STANDALONE.md** - Why standalone architecture

---

## Troubleshooting

### "MCP server not found"
→ Check path in `~/.cursor/mcp-config.json` is absolute and correct

### "Permission denied"
→ Run `~/mcp-screenshot-server/scripts/check_permissions.sh all`

### "Application not running"
→ Start the application first, then try again

---

## What This Project Provides

This ShammyTime repository includes:
- ✅ WoW addon code (Lua files)
- ✅ MCP Screenshot Server source code (for copying out)
- ✅ Documentation

**But the MCP server should be installed to `~/mcp-screenshot-server` to use it.**

---

## Summary

1. **Copy** `mcp-screenshot-server/` to `~/mcp-screenshot-server`
2. **Install** dependencies: `npm install`
3. **Configure** globally in `~/.cursor/mcp-config.json`
4. **Use** in any Cursor project

That's it! The tool is now available everywhere.

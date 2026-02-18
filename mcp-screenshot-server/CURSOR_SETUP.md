# Cursor Setup Guide

This guide explains how to integrate the MCP Screenshot Server with Cursor.

## Important: Global Installation

**This MCP server should be installed globally**, not in a project directory. This allows you to use it across all your Cursor projects (WoW, other games, any application).

## Quick Setup

### Step 1: Install to Permanent Location

```bash
# Install to home directory (recommended)
cp -r mcp-screenshot-server ~/mcp-screenshot-server

# Or clone if separate repo
# git clone <repo-url> ~/mcp-screenshot-server

cd ~/mcp-screenshot-server
npm install
```

### Step 2: Configure Cursor Globally

Add to your **global** Cursor MCP configuration:

**macOS/Linux**: `~/.cursor/mcp-config.json`  
**Windows**: `%APPDATA%\.cursor\mcp-config.json`

Or via: **Cursor Settings** → **Features** → **MCP Servers**

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

**Replace `/Users/YOUR_USERNAME/` with your actual home directory path.**

### Why Global Configuration?

- ✅ Available in **all** Cursor projects
- ✅ Not tied to ShammyTime addon
- ✅ Can capture **any** application window
- ✅ Single installation, multiple uses

### Step 3: Grant Permissions

Run the permission checker:

```bash
./scripts/check_permissions.sh all
```

If permissions are missing:

1. **Screen Recording**:
   - Open System Preferences → Security & Privacy → Privacy → Screen Recording
   - Add and enable your terminal application

2. **Accessibility**:
   - Open System Preferences → Security & Privacy → Privacy → Accessibility
   - Add and enable your terminal application

3. Restart your terminal and Cursor

### Step 4: Test the Integration

Open Cursor and try these prompts with an agent:

1. **Check permissions**:
   ```
   Use the check_permissions tool to verify screenshot permissions
   ```

2. **List windows**:
   ```
   Use the list_windows tool to show all available windows
   ```

3. **Capture a screenshot** (with WoW running):
   ```
   Use the capture_window tool to take a screenshot of World of Warcraft
   ```

## Configuration Options

### Basic Configuration

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

### With Environment Variables

```json
{
  "mcpServers": {
    "screenshot": {
      "command": "node",
      "args": ["/path/to/mcp-screenshot-server/src/index.js"],
      "env": {
        "DEBUG": "true",
        "LOG_LEVEL": "info"
      }
    }
  }
}
```

### Using npm script

```json
{
  "mcpServers": {
    "screenshot": {
      "command": "npm",
      "args": ["start"],
      "cwd": "/path/to/mcp-screenshot-server"
    }
  }
}
```

## Example Agent Prompts

### Basic Screenshot Capture

**Prompt**:
```
Take a screenshot of World of Warcraft and show it to me
```

**What the agent will do**:
1. Invoke `capture_window` with `window_name: "World of Warcraft"`
2. Return the image data or file path
3. Display the screenshot

### Find Available Windows

**Prompt**:
```
What applications are currently running that I can screenshot?
```

**What the agent will do**:
1. Invoke `list_windows` with no filters
2. Parse the results
3. List applications with window counts

### Capture Specific Window

**Prompt**:
```
List all World of Warcraft windows and capture the first one
```

**What the agent will do**:
1. Invoke `list_windows` with `application_name: "World of Warcraft"`
2. Get the first window ID
3. Invoke `capture_window` with that window ID
4. Return the screenshot

### Check Setup

**Prompt**:
```
Verify that screenshot permissions are properly configured
```

**What the agent will do**:
1. Invoke `check_permissions`
2. Report which permissions are granted
3. Provide instructions for any missing permissions

## Advanced Usage

### Capture and Analyze

**Prompt**:
```
Take a screenshot of WoW and tell me what buffs I have
```

**What the agent will do**:
1. Invoke `capture_window` with `return_base64: true`
2. Analyze the image (using vision capabilities)
3. Identify buff icons in the top-right corner
4. List the buffs

### Time-Series Analysis

**Prompt**:
```
Take screenshots of WoW every 30 seconds for the next 5 minutes and track my health
```

**What the agent will do**:
1. Set up a loop to capture screenshots every 30 seconds
2. Invoke `capture_window` each time
3. Analyze health bar in each screenshot
4. Create a timeline of health values

### Multi-Application Monitoring

**Prompt**:
```
Show me screenshots of all my game windows
```

**What the agent will do**:
1. Invoke `list_windows` to find all windows
2. Filter for game applications
3. Invoke `capture_window` for each game window
4. Display all screenshots

## Troubleshooting

### "MCP server not found"

**Problem**: Cursor can't find the MCP server

**Solution**:
1. Verify the path in your MCP config is absolute and correct
2. Ensure `node` is in your PATH
3. Try running the server manually: `node /path/to/src/index.js`
4. Restart Cursor

### "Permission denied" errors

**Problem**: macOS permissions not granted

**Solution**:
1. Run `./scripts/check_permissions.sh all`
2. Grant missing permissions in System Preferences
3. Restart your terminal
4. Restart Cursor

### "Application not running"

**Problem**: Trying to capture a window that doesn't exist

**Solution**:
1. Start the application first
2. Use `list_windows` to verify the application is visible
3. Check the exact application name (case-sensitive)

### Server crashes or hangs

**Problem**: MCP server becomes unresponsive

**Solution**:
1. Check Cursor logs for error messages
2. Try running the server manually to see errors
3. Verify Node.js version (18+ required)
4. Restart Cursor

### Screenshots are blank or corrupted

**Problem**: Captured images are empty or invalid

**Solution**:
1. Verify Screen Recording permission is granted
2. Try capturing a different application
3. Check if the window is actually visible (not minimized behind other windows)
4. Try using `window_id` instead of `window_name`

## Performance Tips

### For Frequent Captures

If you need to capture screenshots frequently:

1. **Use window_id instead of window_name**: Faster lookup
   ```javascript
   // First, get the window ID once
   const windows = await mcp.invoke("list_windows", {
     application_name: "World of Warcraft"
   });
   const windowId = windows.windows[0].id;
   
   // Then reuse it for multiple captures
   await mcp.invoke("capture_window", { window_id: windowId });
   ```

2. **Use return_base64: false for large images**: Avoid encoding overhead
   ```javascript
   await mcp.invoke("capture_window", {
     window_name: "World of Warcraft",
     return_base64: false  // Returns file path instead
   });
   ```

3. **Use JPG format for smaller files**: If quality isn't critical
   ```javascript
   await mcp.invoke("capture_window", {
     window_name: "World of Warcraft",
     format: "jpg"
   });
   ```

### For Batch Operations

When capturing multiple windows:

1. List all windows once, then capture by ID
2. Use parallel invocations if possible
3. Clean up temporary files after processing

## Security Considerations

### Permissions

The MCP server requires:
- **Screen Recording**: To capture window contents
- **Accessibility**: To query window information

These are powerful permissions. Only grant them if you trust the server.

### File Storage

By default, screenshots are stored in `/tmp/` with predictable names. Consider:
- Cleaning up temporary files after use
- Using `return_base64: true` to avoid file storage
- Implementing custom storage paths if needed

### Network Access

The MCP server runs locally and does not make network requests. All operations are local to your machine.

## Next Steps

1. ✅ Install and configure the MCP server
2. ✅ Grant required permissions
3. ✅ Test with basic prompts
4. 📚 Explore advanced agent workflows
5. 🚀 Integrate with your WoW addon (ShammyTime)

## Support

If you encounter issues:

1. Check the troubleshooting section above
2. Review the main README.md for technical details
3. Run `./scripts/check_permissions.sh all` to verify setup
4. Check Cursor logs for error messages

## Related Documentation

- [README.md](README.md) - Main documentation
- [MCP-SCREENSHOT-PROPOSAL.md](../docs/MCP-SCREENSHOT-PROPOSAL.md) - Architecture proposal
- [BUI-11-research.md](../docs/BUI-11-research.md) - Original research (alternative approach)

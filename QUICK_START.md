# Quick Start: MCP Screenshot Tool

## TL;DR

I've created an **MCP screenshot tool** for Cursor instead of a background daemon. It's better because:

- ✅ On-demand (always fresh screenshots)
- ✅ Zero resources when idle (no daemon)
- ✅ Direct Cursor integration
- ✅ Simpler to use and maintain

## Important: Separate Installation

**The MCP server should be installed outside this addon directory** so you can use it for any project, not just ShammyTime.

## 5-Minute Setup

### 1. Extract and Install

```bash
# Copy the MCP server to a standalone location
cp -r mcp-screenshot-server ~/mcp-screenshot-server

# Or clone it separately if it has its own repo
# git clone <mcp-screenshot-repo-url> ~/mcp-screenshot-server

cd ~/mcp-screenshot-server
npm install
```

### 2. Grant Permissions

```bash
./scripts/check_permissions.sh all
```

If permissions are missing:
- Open **System Preferences** → **Security & Privacy** → **Privacy**
- Add your terminal to **Screen Recording** and **Accessibility**
- Restart terminal

### 3. Configure Cursor

Add to your **global** Cursor MCP configuration (not project-specific):

**Location**: `~/.cursor/mcp-config.json` or Cursor Settings → MCP Servers

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

**Important**: Use the absolute path to where you installed the MCP server.

### 4. Restart Cursor

Restart Cursor to load the MCP server.

### 5. Test It

In Cursor, try these prompts:

```
Use the check_permissions tool to verify setup
```

```
Use the list_windows tool to show all available windows
```

```
Use the capture_window tool to take a screenshot of World of Warcraft
```

## What You Get

### Three MCP Tools

1. **`capture_window`** - Take screenshot of specific window
2. **`list_windows`** - List all available windows
3. **`check_permissions`** - Verify macOS permissions

### Example Agent Workflows

**"Show me my WoW screen"**
→ Agent captures fresh screenshot in <1s

**"What buffs do I have?"**
→ Agent captures screenshot and analyzes buff bar

**"List all my game windows"**
→ Agent shows all running game applications

## Why This Approach?

### vs. Background Daemon (PR #10)

| Feature | Daemon | MCP Tool |
|---------|--------|----------|
| Freshness | Up to 60s old | Always fresh (<1s) |
| Resources | Always running | Zero when idle |
| Setup | Complex (launchd) | Simple (npm install) |
| Integration | File-based | Direct tool call |
| Development | 6-7 hours | 4-6 hours (done!) |

## Documentation

- **Setup Guide**: `mcp-screenshot-server/CURSOR_SETUP.md`
- **Technical Docs**: `mcp-screenshot-server/README.md`
- **Architecture**: `docs/MCP-SCREENSHOT-PROPOSAL.md`
- **Comparison**: `docs/MCP-VS-DAEMON-COMPARISON.md`
- **Summary**: `docs/MCP-IMPLEMENTATION-SUMMARY.md`

## Troubleshooting

### "Permission denied"
→ Grant Screen Recording and Accessibility permissions in System Preferences

### "Application not running"
→ Start World of Warcraft first

### "MCP server not found"
→ Verify path in `.cursor/mcp-config.json` is correct

### Still stuck?
→ Run `./scripts/check_permissions.sh all` to diagnose

## Next Steps

1. ✅ Test the setup
2. ✅ Try example prompts
3. ✅ Integrate with your workflow
4. 📚 Read full documentation if needed

## Git Info

- **Branch**: `cursor/mcp-screenshot-tool-0320`
- **Commits**: 2 commits, 16 files, 2,741 lines
- **Status**: Ready for review and testing

---

**Questions?** Check the documentation in `mcp-screenshot-server/` or `docs/`

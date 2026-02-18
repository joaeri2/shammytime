# Why This Should Be Standalone

## The Problem with Project-Embedded Tools

When the MCP Screenshot Server was initially placed inside the ShammyTime addon directory, it created several limitations:

### ❌ Issues with Project-Embedded Installation

1. **Limited Scope**: Only available when working on ShammyTime project
2. **Coupling**: Tool tied to a specific addon/project
3. **Duplication**: Need to copy to other projects to use elsewhere
4. **Updates**: Hard to update across multiple projects
5. **Conceptual Confusion**: Screenshot tool isn't really part of WoW addon

### ✅ Benefits of Standalone Installation

1. **Universal Access**: Available in **all** Cursor projects
2. **Any Application**: Capture screenshots of any app, not just WoW
3. **Single Source**: One installation, globally accessible
4. **Easy Updates**: Update once, affects all projects
5. **Clean Architecture**: Tools separate from project code

---

## Real-World Use Cases

### Use Case 1: Multiple Game Projects

You're working on:
- ShammyTime (WoW addon)
- Discord bot for game communities
- Game streaming overlay tool

**With Standalone MCP**:
- Install once to `~/mcp-screenshot-server`
- Use in all three projects
- Capture WoW, Discord, OBS, any game

**Without Standalone**:
- Copy tool to each project
- Maintain three separate installations
- Update each one individually

---

### Use Case 2: Cross-Application Workflows

**Scenario**: You want Cursor to help you debug a UI issue

**Agent Workflow**:
```
1. "Capture a screenshot of my app"
2. "Capture a screenshot of the design in Figma"
3. "Compare these two screenshots and tell me what's different"
```

**With Standalone MCP**:
- Works seamlessly across applications
- One tool, multiple captures

**Without Standalone**:
- Tool only available in one project
- Can't capture other applications

---

### Use Case 3: Team Collaboration

**Scenario**: Your team wants to use the screenshot tool

**With Standalone MCP**:
```bash
# Team member installs once
git clone <mcp-screenshot-repo> ~/mcp-screenshot-server
cd ~/mcp-screenshot-server
npm install

# Configure Cursor globally
# Done! Works in all projects
```

**Without Standalone**:
- Each project needs the tool
- Team members install multiple times
- Inconsistent versions across projects

---

## Installation Architecture

### Recommended Structure

```
Home Directory (~/)
├── mcp-screenshot-server/        ← Standalone installation
│   ├── src/
│   ├── scripts/
│   └── package.json
│
├── Projects/
│   ├── shammytime/               ← WoW addon (uses MCP)
│   │   ├── ShammyTime.lua
│   │   └── ... (no MCP server here)
│   │
│   ├── discord-bot/              ← Discord bot (uses MCP)
│   │   └── ... (no MCP server here)
│   │
│   └── game-overlay/             ← Overlay tool (uses MCP)
│       └── ... (no MCP server here)
│
└── .cursor/
    └── mcp-config.json           ← Global config pointing to ~/mcp-screenshot-server
```

### Why This Works

1. **Single Installation**: `~/mcp-screenshot-server` installed once
2. **Global Configuration**: `~/.cursor/mcp-config.json` points to it
3. **Universal Access**: All projects can use the tool
4. **Clean Separation**: Projects don't contain tool code

---

## Configuration Comparison

### ❌ Project-Specific (Bad)

**Location**: `/path/to/shammytime/.cursor/mcp-config.json`

```json
{
  "mcpServers": {
    "screenshot": {
      "command": "node",
      "args": ["./mcp-screenshot-server/src/index.js"]
    }
  }
}
```

**Problems**:
- Relative path (only works in this project)
- Need to copy tool to other projects
- Each project has its own config

### ✅ Global (Good)

**Location**: `~/.cursor/mcp-config.json`

```json
{
  "mcpServers": {
    "screenshot": {
      "command": "node",
      "args": ["/Users/yourname/mcp-screenshot-server/src/index.js"]
    }
  }
}
```

**Benefits**:
- Absolute path (works everywhere)
- Single installation
- One config for all projects

---

## Migration Guide

If you currently have the MCP server inside a project:

### Step 1: Copy to Standalone Location

```bash
# From inside the project directory
cp -r mcp-screenshot-server ~/mcp-screenshot-server
```

### Step 2: Install Dependencies

```bash
cd ~/mcp-screenshot-server
npm install
```

### Step 3: Update Cursor Configuration

**Remove project-specific config** (if exists):
- Delete `/path/to/project/.cursor/mcp-config.json`

**Add global config**:
- Create/edit `~/.cursor/mcp-config.json`
- Use absolute path to `~/mcp-screenshot-server`

### Step 4: Remove from Project

```bash
# Optional: Remove from project directory
cd /path/to/project
rm -rf mcp-screenshot-server
```

### Step 5: Test

```bash
# Restart Cursor
# Open any project
# Try: "Use the list_windows tool"
```

---

## Best Practices

### ✅ Do This

1. **Install to home directory**: `~/mcp-screenshot-server`
2. **Use global configuration**: `~/.cursor/mcp-config.json`
3. **Use absolute paths**: `/Users/name/mcp-screenshot-server/...`
4. **Keep tools separate**: Don't embed in projects
5. **Version control separately**: MCP server has its own repo

### ❌ Don't Do This

1. ~~Install inside project directories~~
2. ~~Use relative paths in config~~
3. ~~Copy tool to multiple projects~~
4. ~~Mix tool code with project code~~
5. ~~Use project-specific configuration~~

---

## Analogy: System Tools

Think of the MCP Screenshot Server like system tools:

**System Tools** (like `git`, `node`, `npm`):
- Installed once globally
- Available in all projects
- Updated centrally
- Not part of project code

**MCP Screenshot Server**:
- Should be like a system tool
- Installed once globally
- Available in all projects
- Not part of project code

You wouldn't install `git` inside every project directory. Similarly, don't install the MCP server inside projects.

---

## Future: Package Distribution

Eventually, the MCP Screenshot Server could be distributed as:

### npm Global Package

```bash
npm install -g mcp-screenshot-server
```

Then configure:
```json
{
  "mcpServers": {
    "screenshot": {
      "command": "mcp-screenshot-server"
    }
  }
}
```

### Homebrew Package (macOS)

```bash
brew install mcp-screenshot-server
```

### Standalone Binary

```bash
curl -o ~/bin/mcp-screenshot-server https://releases.../mcp-screenshot-server
chmod +x ~/bin/mcp-screenshot-server
```

---

## Summary

**Key Principle**: **Tools should be global, projects should use them**

- ✅ Install MCP server to `~/mcp-screenshot-server`
- ✅ Configure globally in `~/.cursor/mcp-config.json`
- ✅ Use in all projects
- ✅ Update once, benefits everywhere

This is the correct architecture for reusable development tools.

---

**See Also**:
- [INSTALLATION.md](INSTALLATION.md) - Detailed installation steps
- [CURSOR_SETUP.md](CURSOR_SETUP.md) - Cursor configuration guide
- [README.md](README.md) - Full documentation

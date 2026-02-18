# MCP Screenshot Tool Proposal

## Executive Summary

This document proposes an alternative architecture for BUI-11 (WoW screenshot automation) using the **Model Context Protocol (MCP)** instead of a native macOS application. This approach provides better integration with Cursor, more efficient resource usage, and a simpler architecture.

---

## Problem with Current Approach

The existing proposal (PR #10) designs a native macOS application with:
- Background daemon (launchd) capturing screenshots every 60 seconds
- File-based communication (agents read from folder)
- Complex storage management and cleanup
- 10 sub-tasks, 6-7 hours of development

**Issues**:
1. **Resource Waste**: Captures screenshots continuously, even when not needed
2. **Latency**: Agents read stale screenshots (up to 60 seconds old)
3. **Complexity**: Requires daemon management, file rotation, cleanup scripts
4. **Indirect Integration**: File-based communication is fragile
5. **macOS-Only**: Hard to extend to other platforms

---

## Proposed Solution: MCP Screenshot Tool

### What is MCP?

Model Context Protocol is Cursor's standard for extending AI capabilities through tools. MCP servers expose tools that agents can invoke directly.

### Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Cursor Agent                          │
└─────────────────────────────────────────────────────────┘
                            │
                            │ (invokes tool)
                            ▼
┌─────────────────────────────────────────────────────────┐
│              MCP Screenshot Server                       │
│  - Tool: capture_window                                  │
│  - Tool: list_windows                                    │
│  - Tool: capture_application                             │
└─────────────────────────────────────────────────────────┘
                            │
                            │ (uses native APIs)
                            ▼
┌─────────────────────────────────────────────────────────┐
│              macOS Screenshot APIs                       │
│  - screencapture (CLI)                                   │
│  - AppleScript (window discovery)                        │
└─────────────────────────────────────────────────────────┘
```

### Key Benefits

1. **On-Demand Capture**: Agent requests screenshot exactly when needed
2. **Zero Latency**: Always get fresh screenshot (< 1 second)
3. **No Background Daemon**: No resource consumption when idle
4. **Direct Integration**: Native Cursor tool, not file-based
5. **Simpler Architecture**: Single MCP server, no file management
6. **Extensible**: Easy to add more tools (OCR, image analysis, etc.)
7. **Cross-Platform Ready**: MCP abstraction makes Windows/Linux support easier

---

## MCP Tool Specification

### Tool 1: `capture_window`

**Description**: Capture a screenshot of a specific window by name or ID.

**Parameters**:
```json
{
  "window_name": "World of Warcraft",  // optional
  "window_id": 12345,                  // optional
  "format": "png",                     // optional, default: png
  "return_base64": true                // optional, return image data directly
}
```

**Returns**:
```json
{
  "success": true,
  "image_path": "/tmp/screenshot_123.png",  // if return_base64=false
  "image_data": "base64...",                // if return_base64=true
  "window_id": 12345,
  "window_name": "World of Warcraft",
  "timestamp": "2026-02-18T14:30:22Z",
  "dimensions": {"width": 1920, "height": 1080}
}
```

**Error Cases**:
- Window not found
- Missing permissions
- Capture failed

---

### Tool 2: `list_windows`

**Description**: List all available windows that can be captured.

**Parameters**:
```json
{
  "application_name": "World of Warcraft"  // optional filter
}
```

**Returns**:
```json
{
  "windows": [
    {
      "id": 12345,
      "name": "World of Warcraft",
      "application": "World of Warcraft",
      "is_minimized": false,
      "is_on_current_space": true,
      "bounds": {"x": 0, "y": 0, "width": 1920, "height": 1080}
    }
  ]
}
```

---

### Tool 3: `capture_application`

**Description**: Capture all windows from a specific application.

**Parameters**:
```json
{
  "application_name": "World of Warcraft",
  "combine_windows": false  // optional, merge into single image
}
```

**Returns**:
```json
{
  "success": true,
  "captures": [
    {
      "window_id": 12345,
      "image_path": "/tmp/wow_window_1.png",
      "timestamp": "2026-02-18T14:30:22Z"
    }
  ]
}
```

---

## Implementation Plan

### Phase 1: Basic MCP Server (2-3 hours)

**Goal**: Working MCP server with window capture

**Tasks**:
1. Create MCP server structure (Node.js or Python)
2. Implement `list_windows` tool (AppleScript wrapper)
3. Implement `capture_window` tool (screencapture wrapper)
4. Add permission checking
5. Basic error handling

**Deliverables**:
- `mcp-screenshot-server/` directory
- `server.js` or `server.py`
- `package.json` or `requirements.txt`
- Basic README

---

### Phase 2: Cursor Integration (1 hour)

**Goal**: Configure Cursor to use the MCP server

**Tasks**:
1. Create MCP configuration file
2. Add server to Cursor settings
3. Test tool invocation from agent
4. Document usage examples

**Deliverables**:
- `.cursor/mcp-config.json`
- Usage documentation
- Example prompts

---

### Phase 3: Enhancement & Polish (1-2 hours)

**Goal**: Production-ready features

**Tasks**:
1. Add base64 image return (no file I/O)
2. Add image metadata extraction
3. Improve error messages
4. Add logging
5. Performance optimization

**Deliverables**:
- Enhanced tool capabilities
- Comprehensive error handling
- Performance benchmarks

---

## Technical Implementation

### Option A: Node.js MCP Server (Recommended)

**Pros**:
- Native MCP SDK support
- Fast execution
- Good ecosystem for image processing
- Easy to distribute (npm)

**Structure**:
```
mcp-screenshot-server/
├── package.json
├── src/
│   ├── index.js           # MCP server entry point
│   ├── tools/
│   │   ├── capture.js     # capture_window implementation
│   │   ├── list.js        # list_windows implementation
│   │   └── utils.js       # AppleScript wrappers
│   └── permissions.js     # Permission checking
├── scripts/
│   ├── find_window.applescript
│   └── check_permissions.sh
└── README.md
```

**Dependencies**:
```json
{
  "dependencies": {
    "@modelcontextprotocol/sdk": "^0.5.0",
    "execa": "^8.0.0"
  }
}
```

---

### Option B: Python MCP Server

**Pros**:
- Easier for some developers
- Good for image processing (PIL/Pillow)
- Can use pyobjc for native APIs

**Structure**:
```
mcp-screenshot-server/
├── pyproject.toml
├── src/
│   ├── __init__.py
│   ├── server.py          # MCP server entry point
│   ├── tools/
│   │   ├── capture.py
│   │   ├── list_windows.py
│   │   └── utils.py
│   └── permissions.py
└── README.md
```

**Dependencies**:
```toml
[dependencies]
mcp = "^0.5.0"
pillow = "^10.0.0"
pyobjc-framework-Quartz = "^10.0"  # optional, for native APIs
```

---

## Comparison: MCP vs. Native App

| Aspect | Native App (PR #10) | MCP Tool (Proposed) |
|--------|---------------------|---------------------|
| **Capture Trigger** | Periodic (every 60s) | On-demand (agent request) |
| **Resource Usage** | Continuous (daemon) | Only when invoked |
| **Latency** | Up to 60s stale | Always fresh (< 1s) |
| **Storage** | Disk (with rotation) | Temp files or in-memory |
| **Integration** | File-based | Direct tool invocation |
| **Complexity** | 10 sub-tasks, 6-7 hours | 3 phases, 4-6 hours |
| **Maintenance** | Daemon management, cleanup | Simple server restart |
| **Cross-platform** | macOS only | Easier to extend |
| **Agent UX** | Read from folder | Invoke tool directly |

---

## Migration Path

If the native app approach has already started:

1. **Keep Window Discovery**: Reuse AppleScript code
2. **Keep Capture Logic**: Reuse screencapture wrapper
3. **Remove Daemon**: No launchd needed
4. **Remove Storage Management**: No file rotation needed
5. **Wrap in MCP**: Create MCP server around existing scripts

---

## Example Agent Workflows

### Workflow 1: Basic Screenshot

**Agent Prompt**: "Show me my WoW screen"

**Agent Action**:
```javascript
// Invoke MCP tool
const result = await mcp.invoke("capture_window", {
  window_name: "World of Warcraft",
  return_base64: true
});

// Display to user
display_image(result.image_data);
```

---

### Workflow 2: Find and Capture

**Agent Prompt**: "What buffs do I have in WoW?"

**Agent Action**:
```javascript
// First, list windows to find WoW
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

// Analyze buff bar (top-right corner)
const buffs = analyze_buffs(screenshot.image_data);
return `You have the following buffs: ${buffs.join(", ")}`;
```

---

### Workflow 3: Error Handling

**Agent Prompt**: "Take a screenshot of WoW"

**Agent Action**:
```javascript
try {
  const result = await mcp.invoke("capture_window", {
    window_name: "World of Warcraft"
  });
  return `Screenshot captured: ${result.image_path}`;
} catch (error) {
  if (error.code === "WINDOW_NOT_FOUND") {
    return "World of Warcraft is not running. Please start the game first.";
  } else if (error.code === "PERMISSION_DENIED") {
    return "Screen Recording permission is required. Go to System Preferences → Security & Privacy → Screen Recording";
  } else {
    return `Screenshot failed: ${error.message}`;
  }
}
```

---

## Configuration

### Cursor MCP Configuration

**File**: `.cursor/mcp-config.json` or `cursor-config.json`

```json
{
  "mcpServers": {
    "screenshot": {
      "command": "node",
      "args": ["/path/to/mcp-screenshot-server/src/index.js"],
      "env": {}
    }
  }
}
```

Or for Python:
```json
{
  "mcpServers": {
    "screenshot": {
      "command": "python",
      "args": ["-m", "mcp_screenshot_server"],
      "env": {}
    }
  }
}
```

---

## Testing Strategy

### Unit Tests
- Window discovery (WoW running, not running, multiple instances)
- Screenshot capture (quality, speed, format)
- Permission checking

### Integration Tests
- MCP tool invocation from Cursor
- Error handling and recovery
- Performance (capture time < 1s)

### End-to-End Tests
- Agent workflows (see examples above)
- Multi-window scenarios
- Cross-Space capture

---

## Success Metrics

1. **Performance**: Capture time < 1 second
2. **Reliability**: 99%+ success rate when WoW is running
3. **Resource Usage**: < 50MB memory, 0% CPU when idle
4. **Agent UX**: Single tool call gets fresh screenshot
5. **Setup Time**: < 5 minutes from install to first capture

---

## Risks & Mitigations

| Risk | Mitigation |
|------|------------|
| MCP SDK changes | Pin to stable version, monitor releases |
| Permission issues | Clear error messages, setup guide |
| Performance concerns | Benchmark early, optimize if needed |
| Cross-platform complexity | Start with macOS, abstract platform code |

---

## Recommendation

**Adopt the MCP approach** for the following reasons:

1. ✅ **Better Architecture**: On-demand vs. continuous polling
2. ✅ **Simpler Implementation**: 4-6 hours vs. 6-7 hours
3. ✅ **Better UX**: Direct tool invocation vs. file-based
4. ✅ **More Efficient**: No background daemon
5. ✅ **Easier Maintenance**: Single server vs. multiple scripts + daemon
6. ✅ **Future-Proof**: Easy to extend with more tools

---

## Next Steps

1. **Decision**: Approve MCP approach
2. **Setup**: Create `mcp-screenshot-server/` directory
3. **Implement**: Build basic MCP server (Phase 1)
4. **Test**: Verify tool invocation from Cursor
5. **Document**: Usage guide and examples
6. **Deploy**: Add to Cursor configuration

---

## Questions & Answers

### Q: Can we reuse any work from PR #10?
**A**: Yes! Window discovery (AppleScript) and capture logic (screencapture) can be reused. Only the daemon and storage management are unnecessary.

### Q: What about the 10 sub-tasks already defined?
**A**: Consolidate into 3 phases:
- Phase 1: Window discovery + capture (reuse BUI-11-1, BUI-11-2)
- Phase 2: MCP server wrapper (new work)
- Phase 3: Documentation + testing (reuse BUI-11-8, BUI-11-9)

### Q: Will this work with the existing ShammyTime addon?
**A**: Yes! The MCP tool is complementary. The addon provides in-game data, while the MCP tool provides visual screenshots.

### Q: Can agents still trigger periodic captures if needed?
**A**: Yes! Agents can invoke the tool on a schedule if desired, but it's not required by default.

### Q: What about Windows/Linux support?
**A**: The MCP abstraction makes it easier to add platform-specific implementations later. Start with macOS, then extend.

---

**Document Version**: 1.0  
**Created**: 2026-02-18  
**Author**: Cursor Cloud Agent  
**Status**: Proposal for Review

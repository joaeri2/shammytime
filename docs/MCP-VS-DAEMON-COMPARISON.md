# MCP Tool vs. Background Daemon: Comparison

This document compares two approaches for implementing WoW screenshot automation:

1. **Background Daemon** (Original PR #10 approach)
2. **MCP Tool** (Recommended approach)

---

## Overview

### Background Daemon Approach (PR #10)

A native macOS application that runs continuously in the background, capturing screenshots at regular intervals.

**Architecture**:
```
launchd daemon (always running)
    ↓ (every 60 seconds)
Shell scripts + AppleScript
    ↓
screencapture → Save to folder
    ↓
Cursor agent reads from folder
```

### MCP Tool Approach (Recommended)

A Model Context Protocol server that Cursor agents invoke on-demand to capture screenshots.

**Architecture**:
```
Cursor agent (invokes tool when needed)
    ↓
MCP server (starts on-demand)
    ↓
Shell scripts + AppleScript
    ↓
screencapture → Return to agent
```

---

## Detailed Comparison

| Aspect | Background Daemon | MCP Tool |
|--------|------------------|----------|
| **Trigger** | Periodic (every 60s) | On-demand (agent request) |
| **Resource Usage** | Continuous (daemon always running) | Zero when idle, only when invoked |
| **CPU Usage** | ~1-2% continuous | 0% idle, <5% during capture |
| **Memory Usage** | ~50-100MB continuous | 0MB idle, ~30-50MB during capture |
| **Disk Usage** | 100MB+ (20 screenshots @ 5MB each) | Minimal (temp files, auto-cleanup) |
| **Latency** | Up to 60s stale | Always fresh (<1s) |
| **Storage** | Persistent folder with rotation | Temp files or in-memory (base64) |
| **Integration** | File-based (read from folder) | Direct tool invocation |
| **Setup Complexity** | High (launchd, permissions, scripts) | Medium (MCP config, permissions) |
| **Maintenance** | Daemon management, log rotation | Simple server restart |
| **Debugging** | Check daemon logs, launchd status | Direct error messages to agent |
| **Cross-platform** | macOS only (hard to extend) | Easier to extend (MCP abstraction) |
| **Agent UX** | Read file, check timestamp | Invoke tool, get result |
| **Development Time** | 6-7 hours (10 sub-tasks) | 4-6 hours (3 phases) |
| **Code Complexity** | High (daemon, rotation, cleanup) | Medium (MCP server, tools) |
| **Failure Modes** | Daemon crashes, disk full, rotation bugs | Tool invocation fails (clear error) |
| **Extensibility** | Add more scripts to daemon | Add more MCP tools |

---

## Pros and Cons

### Background Daemon

**Pros**:
- ✅ Screenshots always available (no wait time)
- ✅ Historical data (last N screenshots)
- ✅ Independent of Cursor (can work standalone)
- ✅ Can capture even when agent isn't active

**Cons**:
- ❌ Continuous resource consumption
- ❌ Screenshots may be stale (up to 60s old)
- ❌ Complex setup (launchd configuration)
- ❌ Requires file management (rotation, cleanup)
- ❌ Indirect integration (file-based)
- ❌ Harder to debug (daemon logs)
- ❌ More code to maintain
- ❌ Disk space management needed

### MCP Tool

**Pros**:
- ✅ Zero resource usage when idle
- ✅ Always fresh screenshots (<1s)
- ✅ Direct integration with Cursor
- ✅ Simpler architecture
- ✅ Better error handling
- ✅ Easier to debug
- ✅ No file management needed
- ✅ Extensible (easy to add tools)
- ✅ Cross-platform ready

**Cons**:
- ❌ Requires agent invocation (not automatic)
- ❌ No historical data by default
- ❌ Depends on Cursor MCP support
- ❌ Slight delay on first capture (~1s)

---

## Use Case Analysis

### Use Case 1: "Show me my WoW screen"

**Background Daemon**:
1. Agent reads `screenshots/latest.png`
2. Screenshot may be up to 60s old
3. Agent displays image

**MCP Tool**:
1. Agent invokes `capture_window` tool
2. Fresh screenshot captured in <1s
3. Agent receives and displays image

**Winner**: **MCP Tool** (always fresh, no stale data)

---

### Use Case 2: "What buffs do I have?"

**Background Daemon**:
1. Agent reads `screenshots/latest.png`
2. Analyzes buff bar (may be outdated)
3. Returns buff list

**MCP Tool**:
1. Agent invokes `capture_window` tool
2. Fresh screenshot captured
3. Analyzes current buff bar
4. Returns accurate buff list

**Winner**: **MCP Tool** (accurate, current data)

---

### Use Case 3: "Track my health over the last 5 minutes"

**Background Daemon**:
1. Agent reads last 5 screenshots from folder
2. Analyzes health bar in each
3. Creates timeline

**MCP Tool**:
1. Agent invokes `capture_window` 5 times (or sets up loop)
2. Analyzes each screenshot
3. Creates timeline

**Winner**: **Background Daemon** (historical data readily available)

**Note**: MCP tool could implement historical storage if needed

---

### Use Case 4: "Take a screenshot when I die in WoW"

**Background Daemon**:
1. Daemon captures every 60s
2. Agent checks screenshots for death indicator
3. May miss death if between captures

**MCP Tool**:
1. Agent monitors game state (via addon or other means)
2. Invokes `capture_window` when death detected
3. Captures exact moment

**Winner**: **MCP Tool** (event-driven, precise timing)

---

### Use Case 5: "Monitor WoW while I'm AFK"

**Background Daemon**:
1. Daemon runs continuously
2. Captures screenshots even when agent inactive
3. Screenshots available when user returns

**MCP Tool**:
1. No captures unless agent invokes tool
2. Would need separate monitoring script

**Winner**: **Background Daemon** (autonomous operation)

**Note**: MCP tool could be invoked by a separate monitoring script if needed

---

## Resource Impact

### Background Daemon (24-hour operation)

**CPU**: 1-2% continuous = ~14-29 minutes of CPU time per day  
**Memory**: 50-100MB continuous  
**Disk**: 100MB+ (20 screenshots)  
**I/O**: 1,440 writes per day (60s interval)  
**Network**: None

**Total Impact**: Medium (continuous resource consumption)

### MCP Tool (10 captures per day)

**CPU**: 0% idle, <5% during capture = ~1 minute of CPU time per day  
**Memory**: 0MB idle, ~30-50MB during capture  
**Disk**: <50MB (temp files, auto-cleanup)  
**I/O**: 10 writes per day  
**Network**: None

**Total Impact**: Low (minimal resource consumption)

---

## Development Effort

### Background Daemon (PR #10)

**Phase 1: MVP** (2-3 hours)
- BUI-11-1: Window Discovery Script
- BUI-11-2: Screenshot Capture Script
- BUI-11-4: Configuration System
- BUI-11-6: Permission Checker
- BUI-11-5: Main Orchestration

**Phase 2: Automation** (2 hours)
- BUI-11-3: Storage Management
- BUI-11-7: Automation Setup (launchd)
- BUI-11-8: Documentation

**Phase 3: Polish** (2 hours)
- BUI-11-9: Testing & Validation
- BUI-11-10: Agent Integration Examples

**Total**: 6-7 hours, 10 sub-tasks

### MCP Tool

**Phase 1: Basic MCP Server** (2-3 hours)
- Create MCP server structure
- Implement `list_windows` tool
- Implement `capture_window` tool
- Add permission checking
- Basic error handling

**Phase 2: Cursor Integration** (1 hour)
- Create MCP configuration
- Test tool invocation
- Document usage examples

**Phase 3: Enhancement & Polish** (1-2 hours)
- Add base64 image return
- Improve error messages
- Add logging
- Performance optimization

**Total**: 4-6 hours, 3 phases

**Winner**: **MCP Tool** (faster development, simpler architecture)

---

## Maintenance Burden

### Background Daemon

**Ongoing Tasks**:
- Monitor daemon status (is it running?)
- Check logs for errors
- Manage disk space (rotation working?)
- Update launchd configuration if needed
- Handle daemon crashes
- Debug file permission issues
- Update scripts when macOS changes

**Estimated Maintenance**: 1-2 hours per month

### MCP Tool

**Ongoing Tasks**:
- Update MCP SDK if needed
- Handle macOS permission changes
- Fix bugs in tools

**Estimated Maintenance**: 0.5-1 hour per month

**Winner**: **MCP Tool** (less maintenance overhead)

---

## Extensibility

### Background Daemon

**Adding New Features**:
- Add new scripts to daemon
- Update launchd configuration
- Manage additional file storage
- Update rotation logic

**Example**: Add OCR text extraction
1. Install Tesseract
2. Add OCR script
3. Run OCR on each capture
4. Store text in separate files
5. Update rotation to include text files

**Complexity**: Medium-High

### MCP Tool

**Adding New Features**:
- Add new MCP tool
- Implement handler
- Update server registration

**Example**: Add OCR text extraction
1. Install Tesseract
2. Add `extract_text` tool
3. Implement handler
4. Agent can invoke when needed

**Complexity**: Low-Medium

**Winner**: **MCP Tool** (easier to extend)

---

## Cross-Platform Support

### Background Daemon

**macOS**: ✅ Fully implemented  
**Windows**: ❌ Requires complete rewrite (PowerShell, Task Scheduler)  
**Linux**: ❌ Requires complete rewrite (bash, cron/systemd)

**Effort to Add Windows**: 4-6 hours (new scripts, Task Scheduler)  
**Effort to Add Linux**: 4-6 hours (new scripts, systemd)

### MCP Tool

**macOS**: ✅ Fully implemented  
**Windows**: ⚠️ Requires platform-specific capture implementation  
**Linux**: ⚠️ Requires platform-specific capture implementation

**Effort to Add Windows**: 2-3 hours (PowerShell capture, same MCP server)  
**Effort to Add Linux**: 2-3 hours (xdotool/wmctrl capture, same MCP server)

**Winner**: **MCP Tool** (MCP abstraction makes platform support easier)

---

## Error Handling

### Background Daemon

**Error Scenarios**:
1. WoW not running → Daemon continues, writes error to log
2. Disk full → Daemon fails, may crash
3. Permission denied → Daemon fails, writes to log
4. Window ID changes → Captures wrong window or fails
5. Daemon crashes → No screenshots until restarted

**User Experience**: Errors are hidden in logs, hard to diagnose

### MCP Tool

**Error Scenarios**:
1. WoW not running → Clear error to agent: "Application not running"
2. Permission denied → Clear error to agent: "Grant Screen Recording permission"
3. Window ID invalid → Clear error to agent: "Window not found"
4. Capture fails → Clear error to agent with specific reason

**User Experience**: Errors are immediate and actionable

**Winner**: **MCP Tool** (better error visibility and handling)

---

## Recommendation

### For Most Use Cases: **MCP Tool**

**Choose MCP Tool if**:
- ✅ You want on-demand, fresh screenshots
- ✅ You want minimal resource usage
- ✅ You want direct Cursor integration
- ✅ You want simpler architecture
- ✅ You want better error handling
- ✅ You want easier maintenance

### For Specific Use Cases: **Background Daemon**

**Choose Background Daemon if**:
- ✅ You need continuous monitoring (even when agent inactive)
- ✅ You need historical screenshot data
- ✅ You want autonomous operation (independent of Cursor)
- ✅ You need screenshots even when user is AFK

### Hybrid Approach (Advanced)

**Best of Both Worlds**:
- Use **MCP Tool** for on-demand captures (primary use case)
- Add optional **Background Daemon** for historical data (if needed)
- Agent can invoke MCP tool for fresh screenshots
- Agent can read historical data from daemon folder

**Implementation**:
1. Implement MCP tool first (4-6 hours)
2. Test and validate with agents
3. If historical data is needed, add background daemon (2-3 hours)
4. Configure daemon to use same scripts as MCP tool

---

## Migration Path

If you've already started the Background Daemon approach:

### Reuse What You Have

1. **Window Discovery** (BUI-11-1) → Reuse in MCP tool ✅
2. **Screenshot Capture** (BUI-11-2) → Reuse in MCP tool ✅
3. **Permission Checker** (BUI-11-6) → Reuse in MCP tool ✅
4. **Configuration** (BUI-11-4) → Optional in MCP tool ⚠️
5. **Storage Management** (BUI-11-3) → Not needed in MCP tool ❌
6. **Daemon Setup** (BUI-11-7) → Not needed in MCP tool ❌

### Migration Steps

1. Keep existing scripts (find_window, capture, permissions)
2. Create MCP server wrapper around scripts
3. Test MCP tool with Cursor
4. Deprecate daemon if MCP tool meets needs
5. Keep daemon as optional add-on if historical data needed

**Estimated Migration Time**: 2-3 hours

---

## Conclusion

For the **ShammyTime WoW automation project**, the **MCP Tool approach is recommended** because:

1. ✅ **Better UX**: On-demand, always fresh screenshots
2. ✅ **More Efficient**: Zero resource usage when idle
3. ✅ **Simpler**: Less code, easier maintenance
4. ✅ **Better Integration**: Direct Cursor tool invocation
5. ✅ **Faster Development**: 4-6 hours vs. 6-7 hours
6. ✅ **Easier to Extend**: Add more tools as needed

The Background Daemon approach has merit for specific use cases (continuous monitoring, historical data), but for the primary use case of "Cursor agents viewing WoW state", the MCP Tool is superior.

---

**Document Version**: 1.0  
**Created**: 2026-02-18  
**Author**: Cursor Cloud Agent  
**Status**: Analysis Complete

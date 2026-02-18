# BUI-11: WoW Auto-Screenshot Research & Sub-Tasks

## Executive Summary

This document outlines the technical research and sub-task breakdown for implementing an automated screenshot capture system for World of Warcraft on macOS. The system will enable Cursor agents to "see" the game state by reading screenshots from a designated folder.

---

## Technical Research

### macOS Screenshot Capabilities

#### 1. **screencapture** (Built-in CLI Tool)

**Capabilities:**
- Capture entire screen, specific windows, or regions
- Window-specific capture using window ID: `screencapture -l <windowID> output.png`
- Interactive selection: `screencapture -i output.png`
- Timed capture: `screencapture -T <seconds> output.png`
- No sound: `screencapture -x`
- Format options: PNG (default), JPG, TIFF, PDF

**Key Options:**
```bash
screencapture -l <windowID> -x -o output.png
# -l: window ID
# -x: no sound
# -o: open in Preview (optional)
```

**Pros:**
- Native macOS tool (no installation required)
- Fast and reliable
- Can capture specific windows even when minimized or on different virtual desktops
- Works across Spaces (virtual desktops)

**Cons:**
- Requires window ID (needs discovery mechanism)
- Window ID can change when app restarts

#### 2. **AppleScript** (Window Discovery & Automation)

**Capabilities:**
- Get window IDs for specific applications
- Query window properties (title, bounds, position)
- Trigger actions and integrate with other tools

**Example - Get WoW Window ID:**
```applescript
tell application "System Events"
    tell process "World of Warcraft"
        set windowID to id of window 1
    end tell
end tell
return windowID
```

**Pros:**
- Excellent for window discovery
- Can handle application state checks
- Integrates well with shell scripts

**Cons:**
- Requires accessibility permissions
- Syntax can be verbose
- Error handling needed for when WoW isn't running

#### 3. **CGWindowListCopyWindowInfo** (Advanced - Optional)

**Capabilities:**
- Native macOS API for window management
- More reliable than AppleScript for window discovery
- Can be accessed via Swift/Objective-C or Python (via pyobjc)

**Pros:**
- Most reliable method
- Doesn't require accessibility permissions for reading window info
- Fast execution

**Cons:**
- Requires compiled tool or Python with pyobjc
- More complex implementation

---

## Architecture Design

### Component Breakdown

```
┌─────────────────────────────────────────────────────────┐
│                   WoW Screenshot System                  │
└─────────────────────────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌──────────────┐   ┌──────────────┐   ┌──────────────┐
│   Window     │   │  Screenshot  │   │   Storage    │
│  Discovery   │──▶│   Capture    │──▶│  Management  │
│   Service    │   │   Service    │   │   Service    │
└──────────────┘   └──────────────┘   └──────────────┘
        │                   │                   │
        ▼                   ▼                   ▼
   Find WoW          Take Screenshot      Save & Rotate
   Window ID         (screencapture)      Old Files
```

### Data Flow

1. **Discovery Phase**: Find WoW window ID (on-demand or periodic check)
2. **Capture Phase**: Execute screencapture with window ID
3. **Storage Phase**: Save to designated folder with timestamp
4. **Cleanup Phase**: Rotate/delete old screenshots (optional)
5. **Access Phase**: Cursor agents read latest screenshot(s)

---

## Implementation Approaches

### Approach A: Simple Shell Script (Recommended for MVP)

**Description**: Single bash script that combines AppleScript for window discovery and screencapture for capture.

**Pros:**
- Simple to implement and maintain
- No external dependencies
- Easy to debug
- Works immediately on macOS

**Cons:**
- Requires manual execution or cron/launchd setup
- Less flexible than daemon approach

**Use Case**: Quick MVP, manual or hotkey-triggered captures

---

### Approach B: Background Daemon (launchd)

**Description**: Shell script + launchd plist for automatic periodic execution.

**Pros:**
- Fully automated
- Runs in background
- Configurable interval
- Survives reboots (if configured)

**Cons:**
- More complex setup
- Requires launchd configuration
- Harder to debug

**Use Case**: Production system with automatic periodic captures

---

### Approach C: Python Service (Advanced)

**Description**: Python script using pyobjc for window management and subprocess for screencapture.

**Pros:**
- More robust error handling
- Better logging
- Easier to extend (web API, file watching, etc.)
- Can include image processing (resize, compress)

**Cons:**
- Requires Python environment
- Additional dependencies (pyobjc)
- More complex

**Use Case**: Advanced features like compression, API access, or image analysis

---

### Approach D: Swift Application (Most Robust)

**Description**: Native Swift app with window management and screenshot APIs.

**Pros:**
- Native performance
- Best integration with macOS
- Can include menu bar UI
- App Store distribution possible

**Cons:**
- Requires Xcode and Swift knowledge
- Longer development time
- Compilation required

**Use Case**: Polished product for distribution

---

## Recommended Architecture (Phased Approach)

### Phase 1: MVP (Approach A)
- Simple bash script
- Manual execution or hotkey
- Basic window discovery
- Save to project folder

### Phase 2: Automation (Approach B)
- Add launchd configuration
- Periodic execution (configurable interval)
- Error logging

### Phase 3: Enhancement (Approach C - Optional)
- Python service for advanced features
- Image compression
- Metadata tagging
- Web API for remote access

---

## Storage Strategy

### Folder Structure

```
ShammyTime/
├── screenshots/
│   ├── latest.png           # Symlink to most recent
│   ├── wow_20260218_143022.png
│   ├── wow_20260218_143122.png
│   └── wow_20260218_143222.png
├── scripts/
│   ├── capture_wow.sh       # Main capture script
│   ├── find_wow_window.scpt # AppleScript helper
│   └── install_daemon.sh    # launchd installer
└── config/
    └── screenshot_config.json
```

### File Naming Convention

```
wow_YYYYMMDD_HHMMSS.png
```

Example: `wow_20260218_143022.png` (2026-02-18 at 14:30:22)

### Retention Policy

**Options:**
1. **Keep Last N**: Keep only the last 10/20/50 screenshots
2. **Time-based**: Keep screenshots from last 1/6/24 hours
3. **Unlimited**: Keep all (requires manual cleanup)
4. **Smart**: Keep all from current session, delete on WoW exit

**Recommendation**: Keep last 20 screenshots (rolling window)

---

## Configuration Requirements

### User-Configurable Settings

```json
{
  "capture": {
    "interval_seconds": 60,
    "format": "png",
    "quality": 85,
    "window_name": "World of Warcraft"
  },
  "storage": {
    "folder": "~/ShammyTime/screenshots",
    "retention_count": 20,
    "create_latest_symlink": true
  },
  "logging": {
    "enabled": true,
    "log_file": "~/ShammyTime/logs/screenshot.log"
  }
}
```

---

## Permissions & Security

### Required Permissions

1. **Screen Recording Permission** (macOS 10.15+)
   - Required for window-specific capture
   - User must grant in System Preferences → Security & Privacy → Screen Recording

2. **Accessibility Permission** (for AppleScript)
   - Required if using AppleScript to control applications
   - System Preferences → Security & Privacy → Accessibility

3. **File System Access**
   - Write access to screenshot folder
   - Read access for Cursor agents

### Permission Handling

- Script should check for permissions before running
- Provide clear error messages if permissions missing
- Include setup instructions in README

---

## Integration with Cursor Agents

### Agent Access Pattern

**Option 1: Direct File Access**
```
Agent reads: ~/ShammyTime/screenshots/latest.png
```

**Option 2: Folder Scanning**
```
Agent lists: ~/ShammyTime/screenshots/*.png
Agent sorts by timestamp
Agent reads most recent N files
```

**Option 3: Metadata File**
```
Agent reads: ~/ShammyTime/screenshots/metadata.json
{
  "latest": "wow_20260218_143022.png",
  "timestamp": "2026-02-18T14:30:22Z",
  "window_id": 12345
}
```

**Recommendation**: Option 1 (symlink) + Option 3 (metadata) for best flexibility

---

## Testing Strategy

### Test Cases

1. **Window Discovery**
   - WoW running and focused
   - WoW running but minimized
   - WoW on different virtual desktop (Space)
   - WoW not running
   - Multiple WoW windows

2. **Screenshot Capture**
   - Full window capture
   - Capture quality/size
   - Capture speed (< 1 second)
   - File write success

3. **Storage Management**
   - File naming correctness
   - Symlink creation/update
   - Rotation of old files
   - Disk space handling

4. **Error Handling**
   - Missing permissions
   - Disk full
   - WoW crashes during capture
   - Invalid window ID

5. **Agent Integration**
   - Agent can read latest screenshot
   - Agent can parse timestamp
   - Agent can handle missing files

---

## Sub-Task Breakdown

Based on the research above, here are the recommended sub-tasks:

### 1. **BUI-11-1: Window Discovery Script**
**Scope**: Create AppleScript/shell script to find WoW window ID
- Detect if WoW is running
- Get window ID for active WoW window
- Handle multiple WoW instances
- Error handling for missing app
- Output window ID to stdout or file

**Acceptance Criteria**:
- Script returns valid window ID when WoW is running
- Returns clear error when WoW is not running
- Works across virtual desktops (Spaces)
- Execution time < 0.5 seconds

---

### 2. **BUI-11-2: Screenshot Capture Script**
**Scope**: Create shell script to capture WoW window using screencapture
- Accept window ID as input (from discovery script)
- Execute screencapture with correct parameters
- Save to designated folder with timestamp
- Create/update "latest.png" symlink
- Silent operation (no sound, no preview)

**Acceptance Criteria**:
- Captures window even when on different Space
- PNG file created with correct timestamp naming
- Symlink updated to point to latest
- Execution time < 1 second
- Works with minimized windows

---

### 3. **BUI-11-3: Storage Management & Cleanup**
**Scope**: Implement file rotation and cleanup logic
- Keep only last N screenshots (configurable)
- Delete old files beyond retention limit
- Maintain symlink integrity
- Create folder structure if missing
- Log cleanup actions

**Acceptance Criteria**:
- Correctly maintains rolling window of N files
- Doesn't delete latest.png symlink
- Creates directories as needed
- Handles edge cases (0 files, 1 file, etc.)

---

### 4. **BUI-11-4: Configuration System**
**Scope**: Create configuration file and loading mechanism
- JSON or simple key=value config file
- Settings: interval, retention, folder path, format
- Config validation
- Default values for missing settings
- Config reload without restart

**Acceptance Criteria**:
- Valid JSON/config format
- All settings documented
- Defaults work out-of-box
- Invalid config shows clear error

---

### 5. **BUI-11-5: Main Orchestration Script**
**Scope**: Combine all components into single executable script
- Call window discovery
- Pass window ID to capture script
- Trigger storage cleanup
- Error handling and logging
- Exit codes for success/failure

**Acceptance Criteria**:
- Single command captures screenshot end-to-end
- Clear error messages for each failure mode
- Logs to file (optional)
- Can be run manually or automated
- Exit code 0 on success, non-zero on failure

---

### 6. **BUI-11-6: Permission Checker & Setup**
**Scope**: Create script to verify and guide permission setup
- Check Screen Recording permission
- Check Accessibility permission (if needed)
- Check file write permissions
- Provide instructions for granting permissions
- Test mode to verify everything works

**Acceptance Criteria**:
- Detects missing permissions
- Provides macOS version-specific instructions
- Opens System Preferences to correct pane
- Confirms when permissions are granted

---

### 7. **BUI-11-7: Automation Setup (launchd)**
**Scope**: Create launchd plist and installer for background execution
- launchd plist file for periodic execution
- Configurable interval (default: 60 seconds)
- Install/uninstall scripts
- Start/stop commands
- Logging configuration

**Acceptance Criteria**:
- Daemon runs in background
- Survives user logout (optional)
- Respects configured interval
- Can be started/stopped easily
- Logs to designated file

---

### 8. **BUI-11-8: Documentation & Setup Guide**
**Scope**: Complete user documentation
- Installation instructions
- Permission setup guide
- Configuration options
- Troubleshooting section
- Agent integration examples

**Acceptance Criteria**:
- Clear step-by-step setup instructions
- Screenshots for permission dialogs
- Example configurations
- Common issues and solutions
- Agent usage examples

---

### 9. **BUI-11-9: Testing & Validation**
**Scope**: Test suite and validation scripts
- Test all error conditions
- Test across virtual desktops
- Performance testing (capture speed)
- Long-running stability test
- Agent integration test

**Acceptance Criteria**:
- All test cases pass
- No memory leaks in long-running test
- Capture time < 1 second
- Works reliably across Spaces
- Agent can successfully read screenshots

---

### 10. **BUI-11-10: Cursor Agent Integration Example**
**Scope**: Example prompts and workflows for agents
- Example: "Show me my current WoW screen"
- Example: "What buffs do I have?"
- Example: "Am I in combat?"
- Template prompts for common queries
- Best practices for image analysis

**Acceptance Criteria**:
- At least 5 example prompts
- Documented in README
- Tested with actual agent
- Clear expected outcomes

---

## Dependencies Between Sub-Tasks

```
BUI-11-1 (Window Discovery)
    ↓
BUI-11-2 (Screenshot Capture) ← BUI-11-4 (Configuration)
    ↓
BUI-11-3 (Storage Management)
    ↓
BUI-11-5 (Main Orchestration) ← BUI-11-6 (Permission Checker)
    ↓
BUI-11-7 (Automation Setup)
    ↓
BUI-11-8 (Documentation)
    ↓
BUI-11-9 (Testing)
    ↓
BUI-11-10 (Agent Integration)
```

**Critical Path**: 1 → 2 → 5 → 7 → 8 (MVP)

**Parallel Work**: 3, 4, 6 can be developed alongside 1-2

---

## Estimated Complexity

| Sub-Task | Complexity | Priority | Can Start |
|----------|-----------|----------|-----------|
| BUI-11-1 | Low | High | Immediately |
| BUI-11-2 | Low | High | After 11-1 |
| BUI-11-3 | Low | Medium | After 11-2 |
| BUI-11-4 | Low | Medium | Parallel with 11-1 |
| BUI-11-5 | Medium | High | After 11-2 |
| BUI-11-6 | Medium | High | Parallel with 11-1 |
| BUI-11-7 | Medium | Medium | After 11-5 |
| BUI-11-8 | Low | High | After 11-5 |
| BUI-11-9 | Medium | Medium | After 11-7 |
| BUI-11-10 | Low | Low | After 11-9 |

---

## Alternative Approaches Considered

### 1. **OCR-based Text Extraction**
- Use Tesseract to extract text from screenshots
- Enable text-based queries without image analysis
- **Decision**: Defer to future enhancement (not in MVP)

### 2. **Video Recording Instead of Screenshots**
- Continuous recording vs. periodic snapshots
- **Decision**: Rejected (too much storage, harder for agents to process)

### 3. **Remote Desktop / VNC**
- Stream screen to remote viewer
- **Decision**: Rejected (too complex, not needed for agent use case)

### 4. **Game Addon Integration**
- WoW addon exports game state to file
- **Decision**: Complementary (can work alongside screenshots)

---

## Success Metrics

1. **Reliability**: 99%+ successful captures when WoW is running
2. **Performance**: < 1 second per capture
3. **Storage**: < 100MB for 20 screenshots
4. **Agent Success**: Agent can correctly interpret screenshot 90%+ of time
5. **Setup Time**: < 10 minutes from install to first capture

---

## Future Enhancements (Post-MVP)

1. **Image Compression**: Reduce file size (JPEG, quality settings)
2. **OCR Integration**: Extract text from screenshots automatically
3. **Web API**: Remote access to screenshots
4. **Mobile App**: View screenshots on phone
5. **AI Annotation**: Auto-detect UI elements, buffs, health bars
6. **Multi-Game Support**: Extend to other games
7. **Cloud Sync**: Upload to cloud storage
8. **Hotkey Trigger**: Capture on-demand with keyboard shortcut

---

## References

- [macOS screencapture man page](https://ss64.com/osx/screencapture.html)
- [AppleScript Window Management](https://developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptLangGuide/)
- [launchd plist documentation](https://www.launchd.info/)
- [macOS Screen Recording Permissions](https://support.apple.com/guide/mac-help/control-access-screen-recording-mchld6aa7d23/)

---

## Next Steps

1. Create Linear sub-tasks (BUI-11-1 through BUI-11-10)
2. Assign priorities and dependencies
3. Start with BUI-11-1 (Window Discovery) and BUI-11-6 (Permission Checker)
4. Iterate on MVP (tasks 1, 2, 5, 6, 8)
5. Test with Cursor agents
6. Expand to full automation (task 7)

---

**Document Version**: 1.0  
**Last Updated**: 2026-02-18  
**Author**: Cursor Cloud Agent  
**Status**: Ready for Sub-Task Creation

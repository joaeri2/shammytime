# BUI-11 Sub-Tasks: WoW Auto-Screenshot System

This document contains the breakdown of BUI-11 into actionable sub-tasks. Each sub-task below should be created as a separate Linear issue.

---

## Sub-Task Template

Each sub-task should include:
- **Title**: Clear, concise description
- **Description**: Detailed scope and requirements
- **Acceptance Criteria**: Testable conditions for completion
- **Dependencies**: Other tasks that must be completed first
- **Labels**: Automation, Tooling, etc.
- **Priority**: High/Medium/Low
- **Estimated Complexity**: Low/Medium/High

---

## BUI-11-1: Window Discovery Script

**Title**: Create WoW Window Discovery Script

**Description**:
Implement a script (AppleScript + shell wrapper) that finds the World of Warcraft window ID on macOS. This is the foundation for window-specific screenshot capture.

**Scope**:
- Create AppleScript to query System Events for WoW process
- Get window ID for the active WoW window
- Handle case when WoW is not running (graceful error)
- Handle multiple WoW instances (return first/active)
- Output window ID to stdout for piping to other scripts
- Execution time must be < 0.5 seconds

**Technical Approach**:
```applescript
tell application "System Events"
    if exists (process "World of Warcraft") then
        tell process "World of Warcraft"
            set windowID to id of window 1
            return windowID
        end tell
    else
        error "World of Warcraft is not running"
    end if
end tell
```

**Acceptance Criteria**:
- [ ] Script returns valid window ID when WoW is running
- [ ] Returns clear error message when WoW is not running
- [ ] Works when WoW is on a different virtual desktop (Space)
- [ ] Execution completes in < 0.5 seconds
- [ ] Exit code 0 on success, non-zero on failure
- [ ] Includes basic usage documentation

**Dependencies**: None (can start immediately)

**Priority**: High

**Complexity**: Low

**Labels**: Automation, Tooling

**Files to Create**:
- `scripts/find_wow_window.scpt` - AppleScript
- `scripts/find_wow_window.sh` - Shell wrapper

---

## BUI-11-2: Screenshot Capture Script

**Title**: Implement Screenshot Capture Using screencapture

**Description**:
Create a shell script that captures a specific window using macOS's built-in `screencapture` command. Takes window ID as input and saves PNG to designated folder.

**Scope**:
- Accept window ID as command-line argument
- Use `screencapture -l <windowID>` to capture specific window
- Save to configurable folder (default: `screenshots/`)
- Filename format: `wow_YYYYMMDD_HHMMSS.png`
- Create/update `latest.png` symlink pointing to most recent capture
- Silent operation (no sound, no preview window)
- Works even when window is minimized or on different Space

**Technical Approach**:
```bash
#!/bin/bash
WINDOW_ID=$1
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="${2:-./screenshots}"
OUTPUT_FILE="${OUTPUT_DIR}/wow_${TIMESTAMP}.png"

mkdir -p "$OUTPUT_DIR"
screencapture -l "$WINDOW_ID" -x -o "$OUTPUT_FILE"
ln -sf "$OUTPUT_FILE" "${OUTPUT_DIR}/latest.png"
```

**Acceptance Criteria**:
- [ ] Captures window correctly using provided window ID
- [ ] PNG file created with correct timestamp naming convention
- [ ] Symlink `latest.png` created and updated on each capture
- [ ] Works when WoW is on different virtual desktop
- [ ] Works when WoW window is minimized
- [ ] Execution completes in < 1 second
- [ ] No sound or preview window appears
- [ ] Creates output directory if it doesn't exist
- [ ] Returns appropriate exit codes

**Dependencies**: BUI-11-1 (needs window ID)

**Priority**: High

**Complexity**: Low

**Labels**: Automation, Tooling

**Files to Create**:
- `scripts/capture_wow.sh` - Main capture script

---

## BUI-11-3: Storage Management & Cleanup

**Title**: Implement Screenshot Storage Management and Rotation

**Description**:
Create a script that manages the screenshot folder, implementing file rotation to prevent unlimited disk usage. Keeps only the most recent N screenshots.

**Scope**:
- Delete old screenshots beyond retention limit (configurable, default: 20)
- Preserve `latest.png` symlink
- Sort files by timestamp (filename-based)
- Create folder structure if missing
- Optional: Log cleanup actions
- Handle edge cases (empty folder, single file, etc.)

**Technical Approach**:
```bash
#!/bin/bash
SCREENSHOT_DIR="${1:-./screenshots}"
RETENTION_COUNT="${2:-20}"

cd "$SCREENSHOT_DIR" || exit 1

# Count wow_*.png files (exclude latest.png symlink)
FILE_COUNT=$(ls -1 wow_*.png 2>/dev/null | wc -l)

if [ "$FILE_COUNT" -gt "$RETENTION_COUNT" ]; then
    DELETE_COUNT=$((FILE_COUNT - RETENTION_COUNT))
    ls -1t wow_*.png | tail -n "$DELETE_COUNT" | xargs rm -f
fi
```

**Acceptance Criteria**:
- [ ] Correctly maintains rolling window of N most recent files
- [ ] Does not delete `latest.png` symlink
- [ ] Creates directories as needed
- [ ] Handles empty folder gracefully
- [ ] Handles folder with < N files (no deletions)
- [ ] Sorts by timestamp correctly
- [ ] Optional logging works if enabled
- [ ] No data loss on edge cases

**Dependencies**: BUI-11-2 (needs capture script to create files)

**Priority**: Medium

**Complexity**: Low

**Labels**: Automation, Tooling

**Files to Create**:
- `scripts/cleanup_screenshots.sh` - Cleanup script

---

## BUI-11-4: Configuration System

**Title**: Create Configuration File and Loading System

**Description**:
Implement a configuration system using JSON format to store user preferences for screenshot capture, storage, and automation settings.

**Scope**:
- JSON configuration file with all settings
- Settings: capture interval, retention count, folder path, image format, logging
- Default values for all settings
- Config validation (check types, ranges)
- Shell function to read config values
- Config file location: `config/screenshot_config.json`

**Configuration Schema**:
```json
{
  "capture": {
    "interval_seconds": 60,
    "format": "png",
    "window_name": "World of Warcraft"
  },
  "storage": {
    "folder": "./screenshots",
    "retention_count": 20,
    "create_latest_symlink": true
  },
  "logging": {
    "enabled": true,
    "log_file": "./logs/screenshot.log",
    "log_level": "info"
  }
}
```

**Acceptance Criteria**:
- [ ] Valid JSON format
- [ ] All settings documented with comments/README
- [ ] Default config works out-of-box
- [ ] Config validation detects invalid values
- [ ] Shell helper function reads config correctly
- [ ] Missing config file uses defaults
- [ ] Invalid JSON shows clear error message

**Dependencies**: None (can be developed in parallel)

**Priority**: Medium

**Complexity**: Low

**Labels**: Automation, Tooling

**Files to Create**:
- `config/screenshot_config.json` - Default config
- `scripts/load_config.sh` - Config loader helper

---

## BUI-11-5: Main Orchestration Script

**Title**: Create Main Orchestration Script

**Description**:
Develop the main entry-point script that orchestrates all components: window discovery, screenshot capture, and storage cleanup. This is the script users will run manually or via automation.

**Scope**:
- Call window discovery script to get window ID
- Pass window ID to capture script
- Trigger storage cleanup after capture
- Comprehensive error handling for each step
- Logging to file (optional, based on config)
- Clear exit codes for success/failure
- Command-line options: `--config`, `--verbose`, `--dry-run`

**Technical Flow**:
```
1. Load configuration
2. Find WoW window ID (BUI-11-1)
   └─ If not found: log error, exit 1
3. Capture screenshot (BUI-11-2)
   └─ If failed: log error, exit 2
4. Cleanup old files (BUI-11-3)
   └─ If failed: log warning, continue
5. Log success, exit 0
```

**Acceptance Criteria**:
- [ ] Single command captures screenshot end-to-end
- [ ] Clear error messages for each failure mode
- [ ] Logs to file when logging enabled
- [ ] Can be run manually from command line
- [ ] Exit code 0 on success, non-zero on specific failures
- [ ] `--verbose` flag shows detailed output
- [ ] `--dry-run` flag simulates without capturing
- [ ] Handles missing dependencies gracefully

**Dependencies**: 
- BUI-11-1 (Window Discovery)
- BUI-11-2 (Screenshot Capture)
- BUI-11-3 (Storage Cleanup)
- BUI-11-4 (Configuration)

**Priority**: High

**Complexity**: Medium

**Labels**: Automation, Tooling

**Files to Create**:
- `scripts/capture_wow_auto.sh` - Main orchestration script

---

## BUI-11-6: Permission Checker & Setup Guide

**Title**: Create Permission Checker and Setup Helper

**Description**:
Develop a script that verifies macOS permissions required for screenshot capture and guides users through granting them. Includes Screen Recording and Accessibility permissions.

**Scope**:
- Check if Screen Recording permission is granted
- Check if Accessibility permission is granted (for AppleScript)
- Check file write permissions for screenshot folder
- Provide step-by-step instructions for granting permissions
- Detect macOS version and provide version-specific instructions
- Optional: Open System Preferences to correct pane
- Test mode to verify all permissions and functionality

**Technical Approach**:
```bash
# Screen Recording permission check
if ! screencapture -x /tmp/test.png 2>/dev/null; then
    echo "Screen Recording permission required"
    echo "Go to: System Preferences → Security & Privacy → Screen Recording"
fi

# Accessibility permission check (for AppleScript)
if ! osascript -e 'tell application "System Events" to get name of processes' >/dev/null 2>&1; then
    echo "Accessibility permission required"
    echo "Go to: System Preferences → Security & Privacy → Accessibility"
fi
```

**Acceptance Criteria**:
- [ ] Detects missing Screen Recording permission
- [ ] Detects missing Accessibility permission
- [ ] Checks file write permissions
- [ ] Provides clear, actionable instructions
- [ ] Instructions are macOS version-specific
- [ ] Can open System Preferences to correct pane
- [ ] Test mode confirms all permissions granted
- [ ] Returns exit code indicating permission status

**Dependencies**: None (can be developed in parallel)

**Priority**: High

**Complexity**: Medium

**Labels**: Automation, Tooling

**Files to Create**:
- `scripts/check_permissions.sh` - Permission checker
- `docs/PERMISSIONS.md` - Detailed permission guide

---

## BUI-11-7: Automation Setup (launchd)

**Title**: Create launchd Configuration for Background Automation

**Description**:
Implement launchd plist file and installer scripts to enable automatic periodic screenshot capture in the background. Users can install, start, stop, and configure the daemon.

**Scope**:
- launchd plist file for periodic execution
- Configurable interval (default: 60 seconds)
- Install script (copies plist to ~/Library/LaunchAgents/)
- Uninstall script (removes plist and stops daemon)
- Start/stop commands
- Status check command
- Logging to designated file
- Runs as user (not system-wide)

**launchd Plist Template**:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.shammytime.wowscreenshot</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/capture_wow_auto.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>60</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/wow_screenshot.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/wow_screenshot_error.log</string>
</dict>
</plist>
```

**Acceptance Criteria**:
- [ ] Daemon runs in background after installation
- [ ] Respects configured interval from config file
- [ ] Can be started with `launchctl load`
- [ ] Can be stopped with `launchctl unload`
- [ ] Install script works correctly
- [ ] Uninstall script cleans up completely
- [ ] Logs to designated file
- [ ] Status command shows if daemon is running
- [ ] Survives user logout (optional setting)

**Dependencies**: BUI-11-5 (Main orchestration script)

**Priority**: Medium

**Complexity**: Medium

**Labels**: Automation, Tooling

**Files to Create**:
- `config/com.shammytime.wowscreenshot.plist` - launchd plist
- `scripts/install_daemon.sh` - Installation script
- `scripts/uninstall_daemon.sh` - Uninstallation script
- `scripts/daemon_status.sh` - Status checker

---

## BUI-11-8: Documentation & Setup Guide

**Title**: Write Complete User Documentation

**Description**:
Create comprehensive documentation covering installation, configuration, troubleshooting, and usage of the WoW screenshot system. Includes examples for Cursor agent integration.

**Scope**:
- Installation instructions (step-by-step)
- Permission setup guide (with screenshots)
- Configuration options reference
- Manual usage examples
- Daemon setup and management
- Troubleshooting common issues
- Cursor agent integration examples
- Architecture overview
- FAQ section

**Documentation Structure**:
```
docs/
├── SETUP.md              # Installation and setup
├── PERMISSIONS.md        # Permission guide
├── CONFIGURATION.md      # Config reference
├── USAGE.md             # Usage examples
├── TROUBLESHOOTING.md   # Common issues
├── AGENT_INTEGRATION.md # Cursor agent examples
└── ARCHITECTURE.md      # Technical overview
```

**Key Sections**:
1. **Quick Start** (5-minute setup)
2. **Detailed Installation** (step-by-step)
3. **Permission Setup** (with screenshots of macOS dialogs)
4. **Configuration** (all options explained)
5. **Manual Usage** (running scripts)
6. **Daemon Setup** (background automation)
7. **Troubleshooting** (common errors and solutions)
8. **Agent Integration** (example prompts)

**Acceptance Criteria**:
- [ ] Clear step-by-step installation instructions
- [ ] Screenshots for permission dialogs
- [ ] All configuration options documented
- [ ] At least 5 troubleshooting scenarios covered
- [ ] At least 3 agent integration examples
- [ ] Quick start guide works in < 10 minutes
- [ ] All scripts referenced with usage examples
- [ ] Links to relevant macOS documentation

**Dependencies**: 
- BUI-11-5 (Main script must be complete)
- BUI-11-7 (Daemon setup must be complete)

**Priority**: High

**Complexity**: Low

**Labels**: Tooling, Documentation

**Files to Create**:
- `docs/SETUP.md`
- `docs/PERMISSIONS.md`
- `docs/CONFIGURATION.md`
- `docs/USAGE.md`
- `docs/TROUBLESHOOTING.md`
- `docs/AGENT_INTEGRATION.md`
- `docs/ARCHITECTURE.md`
- Update `README.md` with screenshot system section

---

## BUI-11-9: Testing & Validation

**Title**: Create Test Suite and Validation Scripts

**Description**:
Develop comprehensive tests to validate all components of the screenshot system. Includes unit tests for individual scripts, integration tests, and long-running stability tests.

**Scope**:
- Test script for window discovery (all scenarios)
- Test script for screenshot capture (quality, speed)
- Test script for storage management (rotation, cleanup)
- Integration test (end-to-end workflow)
- Performance test (capture speed, resource usage)
- Long-running stability test (24-hour test)
- Virtual desktop (Spaces) test
- Error condition tests (WoW not running, disk full, etc.)

**Test Categories**:

**1. Window Discovery Tests**:
- WoW running and focused
- WoW minimized
- WoW on different Space
- WoW not running
- Multiple WoW instances

**2. Screenshot Capture Tests**:
- Capture quality (image not corrupted)
- Capture speed (< 1 second)
- File size reasonable (< 5MB for typical window)
- Symlink creation/update
- Works across Spaces

**3. Storage Management Tests**:
- File rotation (keeps only N files)
- Symlink preservation
- Empty folder handling
- Single file handling
- Disk full scenario

**4. Integration Tests**:
- End-to-end capture workflow
- Config loading and application
- Error handling and recovery
- Logging functionality

**5. Performance Tests**:
- Capture time measurement
- CPU usage during capture
- Memory usage over time
- Disk I/O impact

**6. Stability Tests**:
- 24-hour continuous operation
- Memory leak detection
- Error recovery
- Daemon restart handling

**Acceptance Criteria**:
- [ ] All unit tests pass
- [ ] Integration test completes successfully
- [ ] Capture time consistently < 1 second
- [ ] No memory leaks in 24-hour test
- [ ] Works reliably across virtual desktops
- [ ] All error conditions handled gracefully
- [ ] Test results documented
- [ ] CI/CD integration (optional)

**Dependencies**: 
- BUI-11-5 (Main script)
- BUI-11-7 (Daemon)

**Priority**: Medium

**Complexity**: Medium

**Labels**: Automation, Tooling, Testing

**Files to Create**:
- `tests/test_window_discovery.sh`
- `tests/test_screenshot_capture.sh`
- `tests/test_storage_management.sh`
- `tests/test_integration.sh`
- `tests/test_performance.sh`
- `tests/run_all_tests.sh`

---

## BUI-11-10: Cursor Agent Integration Examples

**Title**: Create Cursor Agent Integration Examples and Templates

**Description**:
Develop example prompts, workflows, and best practices for Cursor agents to effectively use the screenshot system. Includes common use cases and template prompts.

**Scope**:
- Example prompts for common queries
- Template workflows for agents
- Best practices for image analysis
- Error handling for missing screenshots
- Performance tips (when to capture vs. read existing)
- Multi-screenshot analysis examples
- Integration with WoW addon data (complementary)

**Example Use Cases**:

**1. Basic Screen Viewing**:
```
Prompt: "Show me my current WoW screen"
Agent Action: Read latest.png, display to user
```

**2. Buff/Debuff Detection**:
```
Prompt: "What buffs do I currently have?"
Agent Action: Read latest.png, analyze top-right corner, list buffs
```

**3. Combat Status**:
```
Prompt: "Am I in combat?"
Agent Action: Read latest.png, check for combat indicators (red border, etc.)
```

**4. Health/Mana Check**:
```
Prompt: "What's my current health and mana?"
Agent Action: Read latest.png, analyze health/mana bars
```

**5. UI Element Detection**:
```
Prompt: "Is my Windfury buff active?"
Agent Action: Read latest.png, look for Windfury icon in buff bar
```

**6. Time-Series Analysis**:
```
Prompt: "Show me my health over the last 5 minutes"
Agent Action: Read last 5 screenshots, extract health values, create timeline
```

**7. Error Recovery**:
```
Prompt: "Take a fresh screenshot and analyze"
Agent Action: Trigger capture script, wait, read new screenshot
```

**Acceptance Criteria**:
- [ ] At least 7 example use cases documented
- [ ] Template prompts provided for each use case
- [ ] Best practices section included
- [ ] Error handling examples provided
- [ ] Performance considerations documented
- [ ] Tested with actual Cursor agent
- [ ] Expected outcomes documented for each example
- [ ] Integration with addon data shown (optional)

**Dependencies**: 
- BUI-11-9 (Testing complete)
- BUI-11-8 (Documentation complete)

**Priority**: Low

**Complexity**: Low

**Labels**: Tooling, Documentation, Feature

**Files to Create**:
- `docs/AGENT_EXAMPLES.md` - Detailed examples
- `examples/agent_prompts.txt` - Template prompts
- `examples/agent_workflow.md` - Workflow diagrams

---

## Summary Table

| Task | Title | Priority | Complexity | Dependencies | Can Start |
|------|-------|----------|-----------|--------------|-----------|
| BUI-11-1 | Window Discovery Script | High | Low | None | ✅ Immediately |
| BUI-11-2 | Screenshot Capture Script | High | Low | 11-1 | After 11-1 |
| BUI-11-3 | Storage Management | Medium | Low | 11-2 | After 11-2 |
| BUI-11-4 | Configuration System | Medium | Low | None | ✅ Immediately |
| BUI-11-5 | Main Orchestration Script | High | Medium | 11-1,2,3,4 | After 11-2 |
| BUI-11-6 | Permission Checker | High | Medium | None | ✅ Immediately |
| BUI-11-7 | Automation (launchd) | Medium | Medium | 11-5 | After 11-5 |
| BUI-11-8 | Documentation | High | Low | 11-5,7 | After 11-7 |
| BUI-11-9 | Testing & Validation | Medium | Medium | 11-5,7 | After 11-7 |
| BUI-11-10 | Agent Integration Examples | Low | Low | 11-8,9 | After 11-9 |

---

## Recommended Work Phases

### Phase 1: MVP (Minimum Viable Product)
**Goal**: Manual screenshot capture working
- BUI-11-1: Window Discovery
- BUI-11-2: Screenshot Capture
- BUI-11-4: Configuration System
- BUI-11-6: Permission Checker
- BUI-11-5: Main Orchestration

### Phase 2: Automation
**Goal**: Background daemon running
- BUI-11-3: Storage Management
- BUI-11-7: Automation Setup
- BUI-11-8: Documentation

### Phase 3: Polish
**Goal**: Production-ready system
- BUI-11-9: Testing & Validation
- BUI-11-10: Agent Integration Examples

---

## Notes for Task Assignment

- **Parallel Work**: Tasks 11-1, 11-4, and 11-6 can be worked on simultaneously
- **Critical Path**: 11-1 → 11-2 → 11-5 → 11-7 → 11-8
- **Quick Wins**: 11-1 and 11-2 are simple and can be completed quickly
- **Blockers**: 11-5 blocks most downstream work (11-7, 11-8, 11-9)
- **Documentation**: 11-8 should be updated continuously as other tasks complete

---

## Labels to Use in Linear

- **Automation**: All tasks
- **Tooling**: All tasks
- **Feature**: 11-10 (agent integration)
- **Documentation**: 11-8, 11-10
- **Testing**: 11-9

---

**Document Version**: 1.0  
**Last Updated**: 2026-02-18  
**Status**: Ready for Linear Issue Creation

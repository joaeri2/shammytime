# Linear Sub-Tasks Creation Template

Use this template to create 10 Linear issues for BUI-11. Copy the content for each task into Linear's issue creation form.

---

## BUI-11-1: Window Discovery Script

**Title**: Create WoW Window Discovery Script

**Description**:
```
Implement a script (AppleScript + shell wrapper) that finds the World of Warcraft window ID on macOS. This is the foundation for window-specific screenshot capture.

## Scope
- Create AppleScript to query System Events for WoW process
- Get window ID for the active WoW window
- Handle case when WoW is not running (graceful error)
- Handle multiple WoW instances (return first/active)
- Output window ID to stdout for piping to other scripts
- Execution time must be < 0.5 seconds

## Files to Create
- scripts/find_wow_window.scpt - AppleScript
- scripts/find_wow_window.sh - Shell wrapper

## Acceptance Criteria
- [ ] Script returns valid window ID when WoW is running
- [ ] Returns clear error message when WoW is not running
- [ ] Works when WoW is on a different virtual desktop (Space)
- [ ] Execution completes in < 0.5 seconds
- [ ] Exit code 0 on success, non-zero on failure
- [ ] Includes basic usage documentation
```

**Labels**: Automation, Tooling  
**Priority**: High  
**Complexity**: Low  
**Parent**: BUI-11  
**Blocks**: BUI-11-2

---

## BUI-11-2: Screenshot Capture Script

**Title**: Implement Screenshot Capture Using screencapture

**Description**:
```
Create a shell script that captures a specific window using macOS's built-in screencapture command. Takes window ID as input and saves PNG to designated folder.

## Scope
- Accept window ID as command-line argument
- Use screencapture -l <windowID> to capture specific window
- Save to configurable folder (default: screenshots/)
- Filename format: wow_YYYYMMDD_HHMMSS.png
- Create/update latest.png symlink pointing to most recent capture
- Silent operation (no sound, no preview window)
- Works even when window is minimized or on different Space

## Files to Create
- scripts/capture_wow.sh - Main capture script

## Acceptance Criteria
- [ ] Captures window correctly using provided window ID
- [ ] PNG file created with correct timestamp naming convention
- [ ] Symlink latest.png created and updated on each capture
- [ ] Works when WoW is on different virtual desktop
- [ ] Works when WoW window is minimized
- [ ] Execution completes in < 1 second
- [ ] No sound or preview window appears
- [ ] Creates output directory if it doesn't exist
- [ ] Returns appropriate exit codes
```

**Labels**: Automation, Tooling  
**Priority**: High  
**Complexity**: Low  
**Parent**: BUI-11  
**Blocked by**: BUI-11-1  
**Blocks**: BUI-11-5

---

## BUI-11-3: Storage Management & Cleanup

**Title**: Implement Screenshot Storage Management and Rotation

**Description**:
```
Create a script that manages the screenshot folder, implementing file rotation to prevent unlimited disk usage. Keeps only the most recent N screenshots.

## Scope
- Delete old screenshots beyond retention limit (configurable, default: 20)
- Preserve latest.png symlink
- Sort files by timestamp (filename-based)
- Create folder structure if missing
- Optional: Log cleanup actions
- Handle edge cases (empty folder, single file, etc.)

## Files to Create
- scripts/cleanup_screenshots.sh - Cleanup script

## Acceptance Criteria
- [ ] Correctly maintains rolling window of N most recent files
- [ ] Does not delete latest.png symlink
- [ ] Creates directories as needed
- [ ] Handles empty folder gracefully
- [ ] Handles folder with < N files (no deletions)
- [ ] Sorts by timestamp correctly
- [ ] Optional logging works if enabled
- [ ] No data loss on edge cases
```

**Labels**: Automation, Tooling  
**Priority**: Medium  
**Complexity**: Low  
**Parent**: BUI-11  
**Blocked by**: BUI-11-2

---

## BUI-11-4: Configuration System

**Title**: Create Configuration File and Loading System

**Description**:
```
Implement a configuration system using JSON format to store user preferences for screenshot capture, storage, and automation settings.

## Scope
- JSON configuration file with all settings
- Settings: capture interval, retention count, folder path, image format, logging
- Default values for all settings
- Config validation (check types, ranges)
- Shell function to read config values
- Config file location: config/screenshot_config.json

## Files to Create
- config/screenshot_config.json - Default config
- scripts/load_config.sh - Config loader helper

## Acceptance Criteria
- [ ] Valid JSON format
- [ ] All settings documented with comments/README
- [ ] Default config works out-of-box
- [ ] Config validation detects invalid values
- [ ] Shell helper function reads config correctly
- [ ] Missing config file uses defaults
- [ ] Invalid JSON shows clear error message
```

**Labels**: Automation, Tooling  
**Priority**: Medium  
**Complexity**: Low  
**Parent**: BUI-11

---

## BUI-11-5: Main Orchestration Script

**Title**: Create Main Orchestration Script

**Description**:
```
Develop the main entry-point script that orchestrates all components: window discovery, screenshot capture, and storage cleanup. This is the script users will run manually or via automation.

## Scope
- Call window discovery script to get window ID
- Pass window ID to capture script
- Trigger storage cleanup after capture
- Comprehensive error handling for each step
- Logging to file (optional, based on config)
- Clear exit codes for success/failure
- Command-line options: --config, --verbose, --dry-run

## Files to Create
- scripts/capture_wow_auto.sh - Main orchestration script

## Acceptance Criteria
- [ ] Single command captures screenshot end-to-end
- [ ] Clear error messages for each failure mode
- [ ] Logs to file when logging enabled
- [ ] Can be run manually from command line
- [ ] Exit code 0 on success, non-zero on specific failures
- [ ] --verbose flag shows detailed output
- [ ] --dry-run flag simulates without capturing
- [ ] Handles missing dependencies gracefully
```

**Labels**: Automation, Tooling  
**Priority**: High  
**Complexity**: Medium  
**Parent**: BUI-11  
**Blocked by**: BUI-11-1, BUI-11-2, BUI-11-3, BUI-11-4  
**Blocks**: BUI-11-7, BUI-11-8

---

## BUI-11-6: Permission Checker & Setup Guide

**Title**: Create Permission Checker and Setup Helper

**Description**:
```
Develop a script that verifies macOS permissions required for screenshot capture and guides users through granting them. Includes Screen Recording and Accessibility permissions.

## Scope
- Check if Screen Recording permission is granted
- Check if Accessibility permission is granted (for AppleScript)
- Check file write permissions for screenshot folder
- Provide step-by-step instructions for granting permissions
- Detect macOS version and provide version-specific instructions
- Optional: Open System Preferences to correct pane
- Test mode to verify all permissions and functionality

## Files to Create
- scripts/check_permissions.sh - Permission checker
- docs/PERMISSIONS.md - Detailed permission guide

## Acceptance Criteria
- [ ] Detects missing Screen Recording permission
- [ ] Detects missing Accessibility permission
- [ ] Checks file write permissions
- [ ] Provides clear, actionable instructions
- [ ] Instructions are macOS version-specific
- [ ] Can open System Preferences to correct pane
- [ ] Test mode confirms all permissions granted
- [ ] Returns exit code indicating permission status
```

**Labels**: Automation, Tooling  
**Priority**: High  
**Complexity**: Medium  
**Parent**: BUI-11

---

## BUI-11-7: Automation Setup (launchd)

**Title**: Create launchd Configuration for Background Automation

**Description**:
```
Implement launchd plist file and installer scripts to enable automatic periodic screenshot capture in the background. Users can install, start, stop, and configure the daemon.

## Scope
- launchd plist file for periodic execution
- Configurable interval (default: 60 seconds)
- Install script (copies plist to ~/Library/LaunchAgents/)
- Uninstall script (removes plist and stops daemon)
- Start/stop commands
- Status check command
- Logging to designated file
- Runs as user (not system-wide)

## Files to Create
- config/com.shammytime.wowscreenshot.plist - launchd plist
- scripts/install_daemon.sh - Installation script
- scripts/uninstall_daemon.sh - Uninstallation script
- scripts/daemon_status.sh - Status checker

## Acceptance Criteria
- [ ] Daemon runs in background after installation
- [ ] Respects configured interval from config file
- [ ] Can be started with launchctl load
- [ ] Can be stopped with launchctl unload
- [ ] Install script works correctly
- [ ] Uninstall script cleans up completely
- [ ] Logs to designated file
- [ ] Status command shows if daemon is running
- [ ] Survives user logout (optional setting)
```

**Labels**: Automation, Tooling  
**Priority**: Medium  
**Complexity**: Medium  
**Parent**: BUI-11  
**Blocked by**: BUI-11-5

---

## BUI-11-8: Documentation & Setup Guide

**Title**: Write Complete User Documentation

**Description**:
```
Create comprehensive documentation covering installation, configuration, troubleshooting, and usage of the WoW screenshot system. Includes examples for Cursor agent integration.

## Scope
- Installation instructions (step-by-step)
- Permission setup guide (with screenshots)
- Configuration options reference
- Manual usage examples
- Daemon setup and management
- Troubleshooting common issues
- Cursor agent integration examples
- Architecture overview
- FAQ section

## Files to Create
- docs/SETUP.md - Installation and setup
- docs/CONFIGURATION.md - Config reference
- docs/USAGE.md - Usage examples
- docs/TROUBLESHOOTING.md - Common issues
- docs/AGENT_INTEGRATION.md - Cursor agent examples
- docs/ARCHITECTURE.md - Technical overview
- Update README.md with screenshot system section

## Acceptance Criteria
- [ ] Clear step-by-step installation instructions
- [ ] Screenshots for permission dialogs
- [ ] All configuration options documented
- [ ] At least 5 troubleshooting scenarios covered
- [ ] At least 3 agent integration examples
- [ ] Quick start guide works in < 10 minutes
- [ ] All scripts referenced with usage examples
- [ ] Links to relevant macOS documentation
```

**Labels**: Tooling, Documentation  
**Priority**: High  
**Complexity**: Low  
**Parent**: BUI-11  
**Blocked by**: BUI-11-5, BUI-11-7

---

## BUI-11-9: Testing & Validation

**Title**: Create Test Suite and Validation Scripts

**Description**:
```
Develop comprehensive tests to validate all components of the screenshot system. Includes unit tests for individual scripts, integration tests, and long-running stability tests.

## Scope
- Test script for window discovery (all scenarios)
- Test script for screenshot capture (quality, speed)
- Test script for storage management (rotation, cleanup)
- Integration test (end-to-end workflow)
- Performance test (capture speed, resource usage)
- Long-running stability test (24-hour test)
- Virtual desktop (Spaces) test
- Error condition tests (WoW not running, disk full, etc.)

## Files to Create
- tests/test_window_discovery.sh
- tests/test_screenshot_capture.sh
- tests/test_storage_management.sh
- tests/test_integration.sh
- tests/test_performance.sh
- tests/run_all_tests.sh

## Acceptance Criteria
- [ ] All unit tests pass
- [ ] Integration test completes successfully
- [ ] Capture time consistently < 1 second
- [ ] No memory leaks in 24-hour test
- [ ] Works reliably across virtual desktops
- [ ] All error conditions handled gracefully
- [ ] Test results documented
- [ ] CI/CD integration (optional)
```

**Labels**: Automation, Tooling, Testing  
**Priority**: Medium  
**Complexity**: Medium  
**Parent**: BUI-11  
**Blocked by**: BUI-11-5, BUI-11-7

---

## BUI-11-10: Cursor Agent Integration Examples

**Title**: Create Cursor Agent Integration Examples and Templates

**Description**:
```
Develop example prompts, workflows, and best practices for Cursor agents to effectively use the screenshot system. Includes common use cases and template prompts.

## Scope
- Example prompts for common queries
- Template workflows for agents
- Best practices for image analysis
- Error handling for missing screenshots
- Performance tips (when to capture vs. read existing)
- Multi-screenshot analysis examples
- Integration with WoW addon data (complementary)

## Example Use Cases
1. Basic screen viewing
2. Buff/debuff detection
3. Combat status check
4. Health/mana monitoring
5. UI element detection
6. Time-series analysis
7. Error recovery

## Files to Create
- docs/AGENT_EXAMPLES.md - Detailed examples
- examples/agent_prompts.txt - Template prompts
- examples/agent_workflow.md - Workflow diagrams

## Acceptance Criteria
- [ ] At least 7 example use cases documented
- [ ] Template prompts provided for each use case
- [ ] Best practices section included
- [ ] Error handling examples provided
- [ ] Performance considerations documented
- [ ] Tested with actual Cursor agent
- [ ] Expected outcomes documented for each example
- [ ] Integration with addon data shown (optional)
```

**Labels**: Tooling, Documentation, Feature  
**Priority**: Low  
**Complexity**: Low  
**Parent**: BUI-11  
**Blocked by**: BUI-11-8, BUI-11-9

---

## Summary for Linear Project

**Parent Issue**: BUI-11 - WoW auto-screenshot to folder for Cursor agents

**Total Sub-Tasks**: 10

**Priority Breakdown**:
- High: 5 tasks (1, 2, 5, 6, 8)
- Medium: 4 tasks (3, 4, 7, 9)
- Low: 1 task (10)

**Complexity Breakdown**:
- Low: 6 tasks (1, 2, 3, 4, 8, 10)
- Medium: 4 tasks (5, 6, 7, 9)
- High: 0 tasks

**Estimated Total Time**: 6-7 hours

**Critical Path**: BUI-11-1 → BUI-11-2 → BUI-11-5 → BUI-11-7 → BUI-11-8

**Can Start Immediately**: BUI-11-1, BUI-11-4, BUI-11-6

---

## Linear Bulk Import Format (Optional)

If your Linear workspace supports CSV import, use this format:

```csv
Title,Description,Priority,Labels,Parent,Blocked By,Complexity
"Create WoW Window Discovery Script","[See BUI-11-1 description above]",High,"Automation,Tooling",BUI-11,,Low
"Implement Screenshot Capture Using screencapture","[See BUI-11-2 description above]",High,"Automation,Tooling",BUI-11,BUI-11-1,Low
"Implement Screenshot Storage Management and Rotation","[See BUI-11-3 description above]",Medium,"Automation,Tooling",BUI-11,BUI-11-2,Low
"Create Configuration File and Loading System","[See BUI-11-4 description above]",Medium,"Automation,Tooling",BUI-11,,Low
"Create Main Orchestration Script","[See BUI-11-5 description above]",High,"Automation,Tooling",BUI-11,"BUI-11-1,BUI-11-2,BUI-11-3,BUI-11-4",Medium
"Create Permission Checker and Setup Helper","[See BUI-11-6 description above]",High,"Automation,Tooling",BUI-11,,Medium
"Create launchd Configuration for Background Automation","[See BUI-11-7 description above]",Medium,"Automation,Tooling",BUI-11,BUI-11-5,Medium
"Write Complete User Documentation","[See BUI-11-8 description above]",High,"Tooling,Documentation",BUI-11,"BUI-11-5,BUI-11-7",Low
"Create Test Suite and Validation Scripts","[See BUI-11-9 description above]",Medium,"Automation,Tooling,Testing",BUI-11,"BUI-11-5,BUI-11-7",Medium
"Create Cursor Agent Integration Examples and Templates","[See BUI-11-10 description above]",Low,"Tooling,Documentation,Feature",BUI-11,"BUI-11-8,BUI-11-9",Low
```

---

**Instructions**:
1. Create each sub-task as a new Linear issue
2. Set BUI-11 as the parent issue for all sub-tasks
3. Add appropriate labels (Automation, Tooling, Documentation, Testing, Feature)
4. Set dependencies using "Blocked by" relationships
5. Assign to team members based on expertise
6. Start with high-priority tasks that have no dependencies (1, 4, 6)

**Document Version**: 1.0  
**Last Updated**: 2026-02-18

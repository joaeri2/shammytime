# BUI-11 Quick Reference Guide

## TL;DR - What We're Building

An automated screenshot system that captures World of Warcraft windows on macOS and saves them to a folder that Cursor agents can read. This enables agents to "see" what's happening in-game without manual screenshot uploads.

---

## The 10 Sub-Tasks at a Glance

| # | Task | What It Does | Priority |
|---|------|-------------|----------|
| **1** | Window Discovery | Find WoW window ID using AppleScript | 🔴 High |
| **2** | Screenshot Capture | Capture window using `screencapture` | 🔴 High |
| **3** | Storage Management | Delete old screenshots, keep last N | 🟡 Medium |
| **4** | Configuration | JSON config for all settings | 🟡 Medium |
| **5** | Main Orchestration | Combine all scripts into one command | 🔴 High |
| **6** | Permission Checker | Verify Screen Recording permissions | 🔴 High |
| **7** | Automation (launchd) | Background daemon for auto-capture | 🟡 Medium |
| **8** | Documentation | Complete setup and usage guide | 🔴 High |
| **9** | Testing | Test suite and validation | 🟡 Medium |
| **10** | Agent Examples | Example prompts for Cursor agents | 🟢 Low |

---

## How It Works (Architecture)

```
┌─────────────────────────────────────────────────────────┐
│  User runs: ./scripts/capture_wow_auto.sh               │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│  1. Find WoW Window ID (AppleScript)                     │
│     → "World of Warcraft" process → Window ID: 12345    │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│  2. Capture Screenshot (screencapture)                   │
│     → screencapture -l 12345 -x wow_20260218_143022.png │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│  3. Save to Folder                                       │
│     → screenshots/wow_20260218_143022.png               │
│     → screenshots/latest.png (symlink)                  │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│  4. Cleanup Old Files                                    │
│     → Keep only last 20 screenshots                     │
└─────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────┐
│  5. Cursor Agent Reads                                   │
│     → Agent: "Show me my WoW screen"                    │
│     → Reads: screenshots/latest.png                     │
└─────────────────────────────────────────────────────────┘
```

---

## Folder Structure

```
ShammyTime/
├── screenshots/                    # Screenshot storage
│   ├── latest.png                 # Symlink to most recent
│   ├── wow_20260218_143022.png   # Timestamped captures
│   ├── wow_20260218_143122.png
│   └── wow_20260218_143222.png
│
├── scripts/                        # All executable scripts
│   ├── find_wow_window.sh         # Task 1: Window discovery
│   ├── capture_wow.sh             # Task 2: Screenshot capture
│   ├── cleanup_screenshots.sh     # Task 3: Storage cleanup
│   ├── load_config.sh             # Task 4: Config loader
│   ├── capture_wow_auto.sh        # Task 5: Main script
│   ├── check_permissions.sh       # Task 6: Permission checker
│   ├── install_daemon.sh          # Task 7: Daemon installer
│   ├── uninstall_daemon.sh        # Task 7: Daemon uninstaller
│   └── daemon_status.sh           # Task 7: Status checker
│
├── config/                         # Configuration files
│   ├── screenshot_config.json     # Task 4: User settings
│   └── com.shammytime.wowscreenshot.plist  # Task 7: launchd
│
├── docs/                           # Documentation
│   ├── BUI-11-research.md         # Technical research
│   ├── BUI-11-subtasks.md         # This breakdown
│   ├── SETUP.md                   # Task 8: Installation guide
│   ├── PERMISSIONS.md             # Task 6: Permission guide
│   ├── CONFIGURATION.md           # Task 4: Config reference
│   ├── USAGE.md                   # Task 8: Usage examples
│   ├── TROUBLESHOOTING.md         # Task 8: Common issues
│   ├── AGENT_INTEGRATION.md       # Task 10: Agent examples
│   └── ARCHITECTURE.md            # Task 8: Technical details
│
├── tests/                          # Test scripts
│   ├── test_window_discovery.sh   # Task 9: Unit tests
│   ├── test_screenshot_capture.sh
│   ├── test_storage_management.sh
│   ├── test_integration.sh
│   └── run_all_tests.sh
│
├── logs/                           # Log files
│   └── screenshot.log
│
└── examples/                       # Agent integration examples
    ├── agent_prompts.txt          # Task 10: Template prompts
    └── agent_workflow.md          # Task 10: Workflows
```

---

## Work Phases

### Phase 1: MVP (Manual Capture) - ~2-3 hours
**Goal**: Get basic screenshot capture working manually

**Tasks**: 1, 2, 4, 6, 5 (in that order)

**Result**: User can run `./scripts/capture_wow_auto.sh` and get a screenshot

**Test**: 
```bash
./scripts/capture_wow_auto.sh
ls -l screenshots/latest.png  # Should exist
```

---

### Phase 2: Automation (Background Daemon) - ~2 hours
**Goal**: Set up automatic periodic capture

**Tasks**: 3, 7, 8

**Result**: Screenshots captured every 60 seconds automatically

**Test**:
```bash
./scripts/install_daemon.sh
./scripts/daemon_status.sh  # Should show "running"
sleep 120
ls -l screenshots/  # Should have multiple timestamped files
```

---

### Phase 3: Polish (Testing & Examples) - ~2 hours
**Goal**: Production-ready with tests and documentation

**Tasks**: 9, 10

**Result**: Fully tested system with agent integration examples

**Test**:
```bash
./tests/run_all_tests.sh  # All tests pass
# Try agent prompt: "Show me my WoW screen"
```

---

## Key Technical Decisions

### Why AppleScript for Window Discovery?
- Native macOS tool, no dependencies
- Can find windows across virtual desktops (Spaces)
- Reliable window ID retrieval

### Why screencapture?
- Built into macOS (no installation)
- Can capture specific windows by ID
- Works even when window is minimized or on different Space
- Fast (< 1 second)

### Why launchd for Automation?
- Native macOS daemon system
- Reliable scheduling
- Survives reboots (optional)
- User-level (no root required)

### Why JSON for Configuration?
- Human-readable
- Easy to parse in shell (using `jq` or `grep`)
- Standard format
- Supports comments (with preprocessing)

---

## Dependencies & Requirements

### macOS Requirements
- **OS Version**: macOS 10.14+ (Mojave or later)
- **Permissions**: Screen Recording, Accessibility (for AppleScript)
- **Tools**: `screencapture`, `osascript` (built-in)

### Optional Tools
- `jq` - For JSON parsing (can use grep as fallback)
- `fswatch` - For file watching (future enhancement)

### No Installation Required
All core functionality uses built-in macOS tools.

---

## Common Issues & Solutions

### Issue: "Screen Recording permission denied"
**Solution**: 
1. Open System Preferences → Security & Privacy → Screen Recording
2. Add Terminal (or iTerm2) to the allowed apps
3. Restart terminal

### Issue: "World of Warcraft is not running"
**Solution**: 
- Start WoW before running capture script
- Or set up daemon to run continuously (will capture when WoW starts)

### Issue: "Window ID changes after WoW restart"
**Solution**: 
- Window discovery script runs each time (gets fresh ID)
- Not an issue with the orchestration script

### Issue: "Symlink not updating"
**Solution**: 
- Check file permissions in screenshots folder
- Ensure capture script has write access

---

## Agent Integration Examples

### Example 1: View Current Screen
```
User: "Show me my current WoW screen"
Agent: *Reads screenshots/latest.png*
Agent: "Here's your current WoW screen: [displays image]"
```

### Example 2: Check Buffs
```
User: "What buffs do I have?"
Agent: *Reads screenshots/latest.png*
Agent: *Analyzes top-right corner for buff icons*
Agent: "You currently have: Windfury Weapon, Strength of Earth Totem, Mana Spring Totem"
```

### Example 3: Combat Status
```
User: "Am I in combat?"
Agent: *Reads screenshots/latest.png*
Agent: *Checks for red combat border*
Agent: "Yes, you are currently in combat. Your health is at 78%."
```

### Example 4: Trigger Fresh Capture
```
User: "Take a new screenshot and show me"
Agent: *Runs ./scripts/capture_wow_auto.sh*
Agent: *Waits 1 second*
Agent: *Reads screenshots/latest.png*
Agent: "Fresh screenshot captured: [displays image]"
```

---

## Performance Targets

| Metric | Target | Why |
|--------|--------|-----|
| **Capture Time** | < 1 second | Fast enough for real-time queries |
| **File Size** | < 5 MB per screenshot | 20 screenshots = ~100 MB (reasonable) |
| **CPU Usage** | < 5% during capture | Minimal impact on gaming |
| **Memory Usage** | < 50 MB for daemon | Lightweight background process |
| **Reliability** | 99%+ success rate | Consistent captures when WoW running |

---

## Testing Checklist

Before marking BUI-11 as complete, verify:

- [ ] Window discovery works when WoW is running
- [ ] Window discovery fails gracefully when WoW is not running
- [ ] Screenshot capture works across virtual desktops (Spaces)
- [ ] Screenshot capture works when WoW is minimized
- [ ] Symlink updates correctly on each capture
- [ ] File rotation keeps only last N screenshots
- [ ] Configuration file loads correctly
- [ ] Permission checker detects missing permissions
- [ ] Daemon installs and runs in background
- [ ] Daemon respects configured interval
- [ ] All scripts have proper error handling
- [ ] Documentation is complete and accurate
- [ ] Agent can successfully read and analyze screenshots

---

## Next Steps After Sub-Task Creation

1. **Create Linear Issues**: Use `BUI-11-subtasks.md` to create 10 Linear issues
2. **Assign Priorities**: High priority tasks first (1, 2, 5, 6, 8)
3. **Start with Task 1**: Window discovery is the foundation
4. **Parallel Work**: Tasks 1, 4, and 6 can be done simultaneously
5. **Test Incrementally**: Test each task before moving to next
6. **Update Documentation**: Keep docs in sync with implementation

---

## Success Criteria for BUI-11

The parent issue (BUI-11) can be closed when:

1. ✅ All 10 sub-tasks are complete
2. ✅ User can run one command to capture WoW screenshot
3. ✅ Daemon runs in background and captures periodically
4. ✅ Screenshots saved to known folder with timestamp
5. ✅ Cursor agents can read and analyze screenshots
6. ✅ Works with virtual desktops (Spaces) setup
7. ✅ Complete documentation exists
8. ✅ All tests pass

---

## Estimated Total Time

- **Phase 1 (MVP)**: 2-3 hours
- **Phase 2 (Automation)**: 2 hours
- **Phase 3 (Polish)**: 2 hours
- **Total**: 6-7 hours of focused work

---

## Questions to Answer Before Starting

1. **Where should screenshots be saved?**
   - Recommendation: `~/ShammyTime/screenshots/` (user home directory)
   - Alternative: Project folder (if working from specific location)

2. **How many screenshots to keep?**
   - Recommendation: 20 (last 20 minutes at 60s interval)
   - Configurable in config file

3. **What capture interval?**
   - Recommendation: 60 seconds (good balance)
   - Configurable: 30s for active debugging, 120s for passive monitoring

4. **Should daemon survive logout?**
   - Recommendation: No (user-level daemon)
   - Can be changed to system-level if needed

5. **What image format?**
   - Recommendation: PNG (lossless, good for UI)
   - Alternative: JPEG (smaller files, lossy)

---

**Document Version**: 1.0  
**Last Updated**: 2026-02-18  
**Author**: Cursor Cloud Agent  
**Status**: Ready for Implementation

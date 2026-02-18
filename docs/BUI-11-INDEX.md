# BUI-11 Documentation Index

**Complete guide to the WoW Auto-Screenshot System research and implementation plan.**

---

## 📋 Quick Navigation

| Document | Purpose | Read Time | Audience |
|----------|---------|-----------|----------|
| **[SUMMARY](BUI-11-SUMMARY.md)** | Executive overview | 5 min | Everyone |
| **[Quick Reference](BUI-11-quick-reference.md)** | Fast lookup guide | 10 min | Developers |
| **[Sub-Tasks](BUI-11-subtasks.md)** | Detailed task specs | 30 min | Developers |
| **[Research](BUI-11-research.md)** | Technical deep-dive | 45 min | Architects |
| **[Dependency Graph](BUI-11-dependency-graph.md)** | Project planning | 15 min | PMs |
| **[Linear Templates](LINEAR_SUBTASKS_TEMPLATE.md)** | Issue creation | 10 min | PMs |

---

## 🎯 Start Here

### If you're a **Project Manager**:
1. Read: [SUMMARY](BUI-11-SUMMARY.md) (5 min)
2. Review: [Dependency Graph](BUI-11-dependency-graph.md) (15 min)
3. Create issues: [Linear Templates](LINEAR_SUBTASKS_TEMPLATE.md) (10 min)
4. Assign tasks using one of the 3 strategies in the dependency graph

### If you're a **Developer**:
1. Read: [Quick Reference](BUI-11-quick-reference.md) (10 min)
2. Find your task: [Sub-Tasks](BUI-11-subtasks.md) (find your assigned task)
3. Deep dive if needed: [Research](BUI-11-research.md) (for technical questions)

### If you're an **Architect/Tech Lead**:
1. Read: [Research](BUI-11-research.md) (45 min)
2. Review: [Sub-Tasks](BUI-11-subtasks.md) (30 min)
3. Validate: [Dependency Graph](BUI-11-dependency-graph.md) (15 min)
4. Approve or suggest changes

---

## 📚 Document Descriptions

### [BUI-11-SUMMARY.md](BUI-11-SUMMARY.md)
**Executive Summary**

The TL;DR of the entire project. Read this first.

**Contains**:
- What was done (research + breakdown)
- The 10 sub-tasks at a glance
- 3-phase implementation plan
- Key technical decisions
- Next steps for delegation

**Best for**: Getting up to speed quickly

---

### [BUI-11-quick-reference.md](BUI-11-quick-reference.md)
**Quick Reference Guide**

Fast lookup for common questions and implementation details.

**Contains**:
- Architecture diagram (ASCII art)
- Folder structure
- Work phases (MVP → Automation → Polish)
- Common issues & solutions
- Agent integration examples
- Performance targets

**Best for**: Developers during implementation

---

### [BUI-11-subtasks.md](BUI-11-subtasks.md)
**Detailed Sub-Task Breakdown**

Complete specifications for all 10 sub-tasks.

**Contains**:
- Full description for each task
- Scope and requirements
- Acceptance criteria (testable)
- Dependencies and blockers
- Files to create
- Priority and complexity
- Summary table

**Best for**: Developers assigned to specific tasks

---

### [BUI-11-research.md](BUI-11-research.md)
**Technical Research Document**

Deep technical analysis and decision rationale.

**Contains**:
- macOS screenshot capabilities
- Architecture design
- 4 implementation approaches
- Storage strategy
- Permission requirements
- Testing strategy
- Future enhancements
- Alternative approaches considered

**Best for**: Architects and senior developers

---

### [BUI-11-dependency-graph.md](BUI-11-dependency-graph.md)
**Project Planning & Dependencies**

Visual guide to task dependencies and scheduling.

**Contains**:
- Visual dependency graph
- Critical path analysis (8h → 6-7h)
- Parallel work opportunities
- 3 assignment strategies
- Bottleneck analysis
- Gantt chart
- Quick decision guide

**Best for**: Project managers and team leads

---

### [LINEAR_SUBTASKS_TEMPLATE.md](LINEAR_SUBTASKS_TEMPLATE.md)
**Linear Issue Templates**

Copy-paste templates for creating Linear issues.

**Contains**:
- Pre-formatted descriptions for all 10 tasks
- Labels, priorities, dependencies
- Acceptance criteria
- Optional CSV format for bulk import

**Best for**: Creating Linear issues quickly

---

## 🏗️ The 10 Sub-Tasks

| # | Task | Priority | Time | Start |
|---|------|----------|------|-------|
| **1** | Window Discovery Script | 🔴 High | 1h | ✅ Now |
| **2** | Screenshot Capture Script | 🔴 High | 1h | After #1 |
| **3** | Storage Management | 🟡 Medium | 0.5h | After #2 |
| **4** | Configuration System | 🟡 Medium | 1h | ✅ Now |
| **5** | Main Orchestration | 🔴 High | 1.5h | After #1-4 |
| **6** | Permission Checker | 🔴 High | 1.5h | ✅ Now |
| **7** | Automation (launchd) | 🟡 Medium | 1.5h | After #5 |
| **8** | Documentation | 🔴 High | 1h | After #5,7 |
| **9** | Testing & Validation | 🟡 Medium | 2h | After #5,7 |
| **10** | Agent Integration Examples | 🟢 Low | 1h | After #8,9 |

**Total Time**: 6-7 hours (with parallel work)

---

## 🚀 Implementation Phases

### Phase 1: MVP (2-3 hours)
**Tasks**: 1, 2, 4, 5, 6  
**Goal**: Manual screenshot capture working  
**Result**: `./scripts/capture_wow_auto.sh` captures WoW window

### Phase 2: Automation (2 hours)
**Tasks**: 3, 7, 8  
**Goal**: Background daemon running  
**Result**: Screenshots captured every 60 seconds automatically

### Phase 3: Polish (2 hours)
**Tasks**: 9, 10  
**Goal**: Production-ready with tests  
**Result**: Fully tested system with agent examples

---

## 🔑 Key Technical Decisions

| Decision | Rationale |
|----------|-----------|
| **AppleScript** for window discovery | Native, works across Spaces, no dependencies |
| **screencapture** for capture | Built-in, fast (< 1s), works with minimized windows |
| **launchd** for automation | Native macOS daemon, reliable, user-level |
| **JSON** for configuration | Human-readable, easy to parse, standard format |
| **Phased approach** | MVP first, then enhance incrementally |

---

## 📊 Project Stats

- **Total Lines of Documentation**: ~3,000 lines
- **Number of Sub-Tasks**: 10
- **Estimated Implementation Time**: 6-7 hours (parallel) or 12 hours (sequential)
- **Minimum MVP Time**: 3-4 hours
- **Number of Files to Create**: ~25 files
- **Technologies**: Bash, AppleScript, JSON, launchd

---

## 🎓 Learning Resources

### macOS Screenshot APIs
- [screencapture man page](https://ss64.com/osx/screencapture.html)
- [AppleScript Language Guide](https://developer.apple.com/library/archive/documentation/AppleScript/Conceptual/AppleScriptLangGuide/)

### macOS Automation
- [launchd.info](https://www.launchd.info/)
- [macOS Screen Recording Permissions](https://support.apple.com/guide/mac-help/control-access-screen-recording-mchld6aa7d23/)

### Bash Scripting
- [Advanced Bash-Scripting Guide](https://tldp.org/LDP/abs/html/)
- [ShellCheck](https://www.shellcheck.net/) - Bash linter

---

## ❓ FAQ

### Q: Where do I start?
**A**: Read [SUMMARY](BUI-11-SUMMARY.md), then [Quick Reference](BUI-11-quick-reference.md)

### Q: How do I create Linear issues?
**A**: Use [Linear Templates](LINEAR_SUBTASKS_TEMPLATE.md) - copy/paste each section

### Q: Which tasks can run in parallel?
**A**: Tasks 1, 4, and 6 can all start immediately. See [Dependency Graph](BUI-11-dependency-graph.md)

### Q: What's the fastest path to MVP?
**A**: Tasks 1 → 2 → 4 → 5 (skip 3, 6, 7, 8, 9, 10). See "Strategy A" in [Dependency Graph](BUI-11-dependency-graph.md)

### Q: What if I have technical questions?
**A**: Check [Research](BUI-11-research.md) first, then ask the team

### Q: Can we skip any tasks?
**A**: For MVP, you can skip 3, 6, 9, 10. Tasks 1, 2, 4, 5 are essential.

### Q: How do we test this?
**A**: See Task 9 in [Sub-Tasks](BUI-11-subtasks.md) for complete test plan

### Q: What permissions are needed?
**A**: Screen Recording permission (macOS 10.15+). Task 6 handles this.

---

## 🔄 Workflow

```
1. PM reads SUMMARY
   ↓
2. PM creates 10 Linear issues (using templates)
   ↓
3. PM assigns tasks (using dependency graph)
   ↓
4. Developers read Quick Reference
   ↓
5. Developers implement their assigned tasks
   ↓
6. QA tests using acceptance criteria
   ↓
7. Done! 🎉
```

---

## 📦 Deliverables

When all tasks are complete, you will have:

### Scripts (9 files)
- `scripts/find_wow_window.sh` - Window discovery
- `scripts/capture_wow.sh` - Screenshot capture
- `scripts/cleanup_screenshots.sh` - Storage management
- `scripts/load_config.sh` - Config loader
- `scripts/capture_wow_auto.sh` - Main script (entry point)
- `scripts/check_permissions.sh` - Permission checker
- `scripts/install_daemon.sh` - Daemon installer
- `scripts/uninstall_daemon.sh` - Daemon uninstaller
- `scripts/daemon_status.sh` - Status checker

### Configuration (2 files)
- `config/screenshot_config.json` - User settings
- `config/com.shammytime.wowscreenshot.plist` - launchd config

### Documentation (7 files)
- `docs/SETUP.md` - Installation guide
- `docs/PERMISSIONS.md` - Permission setup
- `docs/CONFIGURATION.md` - Config reference
- `docs/USAGE.md` - Usage examples
- `docs/TROUBLESHOOTING.md` - Common issues
- `docs/AGENT_INTEGRATION.md` - Agent examples
- `docs/ARCHITECTURE.md` - Technical details

### Tests (6 files)
- `tests/test_window_discovery.sh`
- `tests/test_screenshot_capture.sh`
- `tests/test_storage_management.sh`
- `tests/test_integration.sh`
- `tests/test_performance.sh`
- `tests/run_all_tests.sh`

### Examples (2 files)
- `examples/agent_prompts.txt`
- `examples/agent_workflow.md`

**Total**: ~25 files

---

## 🎯 Success Criteria

The project is complete when:

- ✅ All 10 sub-tasks are done
- ✅ User can run one command to capture WoW screenshot
- ✅ Daemon runs in background and captures periodically
- ✅ Screenshots saved to known folder with timestamp
- ✅ Cursor agents can read and analyze screenshots
- ✅ Works with virtual desktops (Spaces) setup
- ✅ Complete documentation exists
- ✅ All tests pass

---

## 📞 Support

### For Questions About:
- **Project planning**: See [Dependency Graph](BUI-11-dependency-graph.md)
- **Technical details**: See [Research](BUI-11-research.md)
- **Task specifications**: See [Sub-Tasks](BUI-11-subtasks.md)
- **Quick answers**: See [Quick Reference](BUI-11-quick-reference.md)

### Still Stuck?
1. Check the FAQ above
2. Search the relevant document
3. Ask the team lead
4. Review the original Linear issue (BUI-11)

---

## 🔗 Related Issues

- **BUI-11**: Parent issue (WoW auto-screenshot to folder for Cursor agents)
- **BUI-11-1** through **BUI-11-10**: Sub-tasks (to be created)

---

## 📝 Document History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-02-18 | Initial research and breakdown complete |

---

## 🏁 Next Steps

1. ✅ **Research complete** (you're reading it now!)
2. ⏳ **Create Linear issues** using [templates](LINEAR_SUBTASKS_TEMPLATE.md)
3. ⏳ **Assign tasks** to team members
4. ⏳ **Start development** on tasks 1, 4, 6
5. ⏳ **Test incrementally** after each phase
6. ⏳ **Deploy** and integrate with Cursor agents

---

**Status**: ✅ Research Complete - Ready for Implementation  
**Branch**: `cursor/BUI-11-wow-auto-screenshot-112c`  
**Created**: 2026-02-18  
**Author**: Cursor Cloud Agent

---

## 📄 All Documents at a Glance

```
docs/
├── BUI-11-INDEX.md                  ← YOU ARE HERE
├── BUI-11-SUMMARY.md                (Executive summary)
├── BUI-11-quick-reference.md        (Quick lookup)
├── BUI-11-subtasks.md               (Task specifications)
├── BUI-11-research.md               (Technical deep-dive)
├── BUI-11-dependency-graph.md       (Project planning)
└── LINEAR_SUBTASKS_TEMPLATE.md      (Issue templates)
```

**Total Documentation**: ~3,000 lines across 7 files

---

**Happy coding! 🚀**

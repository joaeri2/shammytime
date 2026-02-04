
Build an Ace3 options system for my WoW TBC Anniversary 2026 addon (Classic-era API) (also remember to reuse things we allready have if possible)

Goal: add an options panel (Interface → AddOns) that controls multiple UI modules (Windfury Bubbles, Shield Indicator, Shamanistic Focus Indicator, Totem Bar, Weapon Imbue Bar). I need sliders, toggles, reset, and a “demo/test mode” that plays a premade animation. I also need fade rules.

Research / confirm environment
	•	Confirm which configuration API is correct for TBC Anniversary 2026 (Classic-era): use Ace3 + Blizzard InterfaceOptions category integration via AceConfig-3.0 + AceConfigDialog-3.0 (AddToBlizOptions).
	•	Confirm embedded Ace3 libs: AceAddon-3.0, AceDB-3.0, AceConfig-3.0, AceConfigDialog-3.0 (AceGUI comes with it).
	•	Make sure SavedVariables work in this client.

Libraries and folder layout
	•	Embed Ace3 inside the addon (don’t depend on the user having external Ace3).
	•	Folder: MyAddon/Libs/...
	•	.toc should load Ace3 XML files first, then addon code files.

Architecture (keep it not messy)
	•	Addon uses AceAddon as the main addon object.
	•	Each UI element is a “module” object with a consistent interface:
	•	:Create() – creates frames/textures once
	•	:ApplyConfig() – reads db.profile. and applies scale/position/alpha/fonts/visibility
	•	:SetEnabled(true/false) – show/hide + disable updates if off
	•	:DemoStart() and :DemoStop() – play/show a premade animation sequence
	•	:Reset() – optional helper, or just rely on db reset + ApplyAll()

SavedVariables / DB shape (important)
	•	Use AceDB-3.0 with defaults = { profile = {...} }.
	•	Store config per module under profile.modules.<ModuleName>.
	•	Store global settings (like global UI scale, master fade, “lock frame movement”) under profile.global.

Example DB structure (implement this exact shape)
	•	profile.global.locked (bool)
	•	profile.global.demoMode (bool)
	•	profile.global.masterScale (number)
	•	profile.global.masterAlpha (0..1)
	•	profile.global.resetConfirm not needed, use a button.

Per-module structure under profile.modules:
For each of:
	•	windfuryBubbles
	•	shieldIndicator
	•	shamanisticFocus
	•	totemBar
	•	weaponImbueBar

Store:
	•	enabled (bool)
	•	scale (number)
	•	alpha (0..1)
	•	pos.point / pos.relPoint / pos.x / pos.y (for anchoring)
	•	font.size (number) where relevant
	•	fade.enabled (bool)
	•	fade.inactiveAlpha (0..1)
	•	fade.conditions (table of toggles like: outOfCombat, noTarget, inactiveBuff, noTotemsPlaced, outOfRange, etc)

Options UI requirements (AceConfig)
Create a clean options UI using AceConfig groups:
	•	Top-level: “General”
	•	MasterScale slider
	•	MasterAlpha slider
	•	Lock toggle (locks dragging if we add drag move)
	•	Demo button: “Play Demo”
	•	Demo toggle: “Demo Mode (keep looping)” optional
	•	Reset button: “Reset All to Defaults”
	•	Then a top-level group: “Modules”
	•	Subgroups per module: Windfury Bubbles, Shield Indicator, Shamanistic Focus, Totem Bar, Weapon Imbue Bar
	•	Each module subgroup contains:
	•	Enable toggle
	•	Scale slider
	•	Alpha slider
	•	Position controls:
	•	X slider, Y slider OR a “Unlock + drag to move + Save position” system
	•	Font size slider (only for modules with text)
	•	Fade subgroup:
	•	Enable fade toggle
	•	Inactive alpha slider
	•	Condition toggles relevant to that module (see below)
	•	Demo button for that module: “Preview”

Fade system (must be centralized)
Implement a shared fade evaluator:
	•	A single MyAddon:EvaluateFade(moduleName) that decides targetAlpha based on module.fade settings + conditions.
	•	Apply with UIFrameFadeIn/UIFrameFadeOut or simple frame:SetAlpha() (fastest: SetAlpha, no animation; optional: animate if easy).
	•	Conditions should be modular:
	•	For Totem Bar: inactive if no totems placed; outOfRange could show red overlay or reduce alpha.
	•	For Shield Indicator: inactive if Lightning Shield / Water Shield not active.
	•	For Windfury Bubbles: inactive if no Windfury procs in last X seconds OR not in combat (configurable later).
	•	For Weapon Imbue Bar: inactive if no imbue active.

Demo/Test mode (must be quick and impressive)
Need “demo mode” that can be triggered:
	•	From General: “Play Demo” plays sequence across all modules for ~10–15 seconds.
	•	From each module: “Preview” plays that module’s own test animation.

Implementation constraints:
	•	Do NOT require real combat events for demo. It should run purely via timers.
	•	Use C_Timer.After / C_Timer.NewTicker (whichever exists in this client) to schedule:
	•	show module, increase alpha, play animation, then fade out, etc.
	•	The demo should not permanently modify saved config (only temporary visuals). Stop demo returns to normal state.

Reset
	•	Provide “Reset All” button:
	•	call AceDB:ResetDB("Default") OR self.db:ResetProfile() depending on chosen pattern
	•	then call ApplyAllConfigs()
	•	Also provide “Reset Module” inside each module subgroup.

Apply flow / performance
	•	Build one function: MyAddon:ApplyAllConfigs() that calls each module’s :ApplyConfig().
	•	Each option set() should update DB + call either module Apply or ApplyAll.
	•	Avoid heavy OnUpdate loops. Use animation groups or simple timers.

Event wiring to drive conditions
	•	Maintain a small state table updated by events:
	•	combat state: PLAYER_REGEN_DISABLED/ENABLED
	•	buffs: UNIT_AURA for player (shield active checks)
	•	totems: TOTEM_UPDATE / PLAYER_TOTEM_UPDATE depending on what exists
	•	weapon imbues: weapon enchant changed event (or polling if needed)
	•	When state changes: call EvaluateFade and ApplyAlpha per affected module.

Deliverables / what to produce in code
	•	Add Ace3 embedded libs and update .toc.
	•	Create files:
	•	Core.lua (AceAddon init, db init, state, ApplyAllConfigs, Demo controller)
	•	Options.lua (AceConfig tables, all UI groups)
	•	Modules/WindfuryBubbles.lua
	•	Modules/ShieldIndicator.lua
	•	Modules/ShamanisticFocus.lua
	•	Modules/TotemBar.lua
	•	Modules/WeaponImbueBar.lua
	•	Each module implements the common functions described above.

UI cleanliness requirement
	•	Options must be structured with groups so it’s not one long page:
	•	General
	•	Modules → each module group
	•	Inside each module: “Appearance”, “Position”, “Fade”, “Demo”, “Reset” as subgroups if needed.

Acceptance criteria
	•	I can open Interface → AddOns → MyAddon and see:
	•	General settings + demo + reset
	•	A tidy “Modules” section with per-module controls
	•	Sliders immediately affect the UI in-game (no reload needed).
	•	Toggling a module hides/shows it cleanly.
	•	Reset restores defaults and updates live.
	•	Demo runs without needing combat.

⸻
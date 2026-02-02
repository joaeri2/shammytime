# Windfury radial — design & plan (single reference)

We are building a WoW TBC Anniversary 2026 add-on with two tightly connected features:
	1.	A clean, reliable Totem Timer UI (track your active totems, remaining durations, range/out-of-range, cooldown-ish feedback, etc.)
	2.	A “Windfury Proc Moment” UI (a radial animation that pops open when Windfury procs, shows fight statistics for Windfury, then collapses away after ~3 seconds)

The goal is not “a WeakAura clone”. The goal is a cohesive, high-quality, WoW-native-looking add-on that still feels flashy when something cool happens.

Important aesthetic rule: the totem UI and the Windfury proc UI must look like they belong to the same add-on. Same textures, same border style, same typography, same spacing.

⸻

Implementation plan (ShammyTime)

Goal:
	•	Totem timer bar (4 totems) — already in ShammyTime; optionally restyle later with shared Media textures.
	•	Windfury proc radial UI — pops on procs, shows aggregated stats (min/avg/max, proc%, proc count, last proc total), closes after ~2.5–3 s.

File layout:
	•	ShammyTime.lua — Core: totem bar, Lightning Shield, weapon imbue, Focused, Windfury stats bar, text popup, combat log (SPELL_DAMAGE 25584), SavedVariables. Exposes API for the Windfury module.
	•	ShammyTime_Media.lua — Single place for Media paths and design constants (center ring + orb set). Load early in TOC.
	•	ShammyTime_CenterRing.lua — Center ring frame; /wfcenter, /wfproc, /wfresize.
	•	ShammyTime_Windfury.lua — Radial UI, center ring (layered), 6 satellites, rune ring; AnimationGroups; SPELL_EXTRA_ATTACKS + damage correlation; /wftest.
	•	AssetTest.lua — Texture tester; /wfassets toggles frame and prints paths.
	•	Media/ — Center ring: wf_center_bg.tga, wf_center_border.tga, wf_center_runes.tga, wf_center_energy.tga (512×512). Orb set: orb_bg, orb_border, glow_soft, ring_runes. All 32-bit TGA, power-of-two.

Loading multiple Lua files (WoW):
	•	TOC lists Lua files in load order; all run in sequence. Later files use globals set by earlier files (no require()).
	•	Core sets ShammyTime = ShammyTime or {} and exposes GetDB, GetWindfuryStats, lastProcTotal. Windfury module and AssetTest use ShammyTime and ShammyTime_Media.

Commands:
	•	/wfassets — Toggle AssetTest frame, print Media paths.
	•	/wftest — Play full radial open/close animation without combat.
	•	/wfproc — Play center “proc pulse” (glow + breathe + rune rotation) without combat.
	•	/st wf radial on|off — Enable/disable radial on proc.

Options (ShammyTimeDB):
	•	wfRadialEnabled — Show radial on Windfury proc (default true).
	•	Existing: windfuryTrackerEnabled, wfPopupEnabled, wfPopupScale, wfPopupHold, etc.

Placeholder assets:
	•	Media paths point to Interface\AddOns\ShammyTime\Media\*.tga. Add real 32-bit power-of-two TGA files; until then SetTexture may show green/missing. /wfassets confirms paths.

⸻

Why this add-on is “hard” (so we design it correctly)

There are 3 tricky parts:

A) “Premium visuals” in WoW are mostly a texture + animation problem, not a complicated frame problem.
B) Windfury proc detection and attributing the “extra attacks” damage to the proc is a combat-log correlation problem.
C) TBC Anniversary 2026 may be a separate install / separate AddOns folder, so testing and file paths need to be clear.  ￼

⸻

Core design vision (the UI experience)

Totem Timer UI (always-on)
	•	A totem bar with 4 slots (Earth/Fire/Water/Air)
	•	Each slot shows:
	•	Totem icon
	•	Timer text (remaining time)
	•	Status styling:
	•	Active = crisp, full alpha
	•	Inactive = desaturated + “washed out”
	•	Out of range = red overlay / warning ring

Windfury “Proc Moment” (temporary)
	•	When Windfury procs:
	•	A single center circle pops in (Windfury icon + “WF!” + maybe last proc total)
	•	Center is layered: bg → energy → border → runes (see “Center ring kit” below)
	•	A rune ring faintly rotates; energy “glows up” with a ~0.8s proc pulse (glow + breathe)
	•	6 smaller circles “spin-open” outward with slight stagger
	•	Each small circle shows one stat: max / avg / min / proc% / proc count / crit% or max hit (you choose exact set)
	•	It holds for ~2.5–3.0 sec
	•	Then collapses back into center and fades out quickly

This is exactly the “feels like you did something badass” moment you described 🔥

⸻

Center ring kit (first milestone) — layered “dead → alive” on proc

The center ring is built from 4 separate texture files stacked on top of each other. Then a simple “proc pulse” animation makes it glow + breathe for ~0.8s.

Make these 4 files (all 512×512, transparent background, export to 32-bit TGA):

	1.	wf_center_bg.tga
		Dark circular disk background (subtle vignette, slightly lighter center).

	2.	wf_center_border.tga
		The bronze/gold ring + bevel + ornament. No interior fill.

	3.	wf_center_runes.tga
		Faint runic ring markings (low contrast). This is what we rotate subtly on proc.

	4.	wf_center_energy.tga
		The “Windfury energy” inside: lightning/air swirl texture (blue-ish), intended to look alive when alpha increases on proc.

	Optional later (not needed for first milestone): wf_center_glow_soft.tga for extra bloom.

Why this split works:
	•	Border stays mostly static (WoW-like).
	•	Runes + energy are what “wake up” on proc.
	•	You can animate energy alpha + scale for pulse and rotate runes for motion.

Exact look rules (so it stays WoW-ish):
	•	Border: bronze/gold, not neon. Small highlights only.
	•	Runes: very subtle (alpha ~0.15–0.30 in-game).
	•	Energy: can be stronger on proc, but normally keep it dim until proc.
	•	No text baked into textures. Text is always FontStrings.

⸻

Gemini prompts (copy/paste) to generate each center layer

Generate them one by one. Tell Gemini transparent background every time. If Gemini keeps adding a background, add: “pure alpha transparency outside the circle, no checkerboard”. Still verify in GIMP.

1) wf_center_bg (512×512)

	“512x512 transparent background. A circular dark fantasy UI disk background for a World of Warcraft style addon. Subtle radial gradient, darker edges (vignette), slightly lighter center, soft inner shading, no border, no runes, no text, perfectly centered circle, symmetric, high quality.”

2) wf_center_border (512×512)

	“512x512 transparent background. A circular ornate bronze-gold ring frame in World of Warcraft UI style. Thick ring with carved details and slight bevel, highlight top-left, shadow bottom-right, no inner fill, no runes, no text, perfectly centered circle, symmetric, high quality.”

3) wf_center_runes (512×512)

	“512x512 transparent background. A faint circular runic glyph ring intended as a subtle overlay behind a UI frame. Low contrast, thin runes spaced evenly around the ring, slightly worn fantasy engraving style, no border frame, no fill, no text, centered circle, symmetric.”

4) wf_center_energy (512×512)

	“512x512 transparent background. A circular magical storm energy texture for a World of Warcraft Windfury proc effect. Blue air-lightning swirl inside a circle, no border, soft wisps, energy concentrated near center, fades to transparent near edges, no text, centered, symmetric.”

⸻

GIMP workflow: turn PNGs into WoW-ready TGA

For each generated PNG:
	1.	Open in GIMP
	2.	Layer → Transparency → Add Alpha Channel
	3.	Remove any fake background (checkerboard pixels or gray): Colors → Color to Alpha… and pick the background color
	4.	Resize to 512×512 if needed: Image → Scale Image
	5.	Export: File → Export As… → .tga
	6.	In export options: disable RLE compression (safe)

Result: wf_center_*.tga ready for WoW. Put them in Interface/AddOns/ShammyTime/Media/ (wf_center_bg.tga etc.).

⸻

WoW code: render the center ring with stacked layers

Layering order (back to front):
	•	bg (BACKGROUND)
	•	energy (ARTWORK) — default low alpha
	•	border (BORDER) — crisp ring
	•	runes (OVERLAY) — low alpha and rotated on proc

	local ADDON = ...
	local MEDIA = "Interface\\AddOns\\"..ADDON.."\\Media\\"

	local TEX_BG     = MEDIA.."wf_center_bg.tga"
	local TEX_BORDER = MEDIA.."wf_center_border.tga"
	local TEX_RUNES  = MEDIA.."wf_center_runes.tga"
	local TEX_ENERGY = MEDIA.."wf_center_energy.tga"

	local f = CreateFrame("Frame", "WF_CenterTest", UIParent)
	f:SetSize(260, 260)
	f:SetPoint("CENTER")
	f:Show()

	f.bg = f:CreateTexture(nil, "BACKGROUND")
	f.bg:SetAllPoints()
	f.bg:SetTexture(TEX_BG)
	f.bg:SetAlpha(1)

	f.energy = f:CreateTexture(nil, "ARTWORK")
	f.energy:SetAllPoints()
	f.energy:SetTexture(TEX_ENERGY)
	f.energy:SetAlpha(0.12)  -- dim idle
	f.energy:SetBlendMode("ADD")  -- makes it feel magical

	f.border = f:CreateTexture(nil, "BORDER")
	f.border:SetAllPoints()
	f.border:SetTexture(TEX_BORDER)
	f.border:SetAlpha(1)

	f.runes = f:CreateTexture(nil, "OVERLAY")
	f.runes:SetAllPoints()
	f.runes:SetTexture(TEX_RUNES)
	f.runes:SetAlpha(0.18)

	-- Text overlay (not baked in)
	f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	f.title:SetPoint("CENTER", 0, 10)
	f.title:SetText("Windfury!")

	f.total = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	f.total:SetPoint("CENTER", 0, -16)
	f.total:SetText("TOTAL: 3245")

⸻

Proc animation: “glow up and comes alive” (pulse + rune rotation)

Animate on proc (~0.8s total):
	•	Energy alpha up then down (quick “ignite” then settle)
	•	A tiny scale “breath” on the whole frame (pop then settle)
	•	Rune rotation (subtle motion)

	local function BuildProcAnim(frame)
	  local g = frame:CreateAnimationGroup()

	  -- Quick pop scale
	  local s1 = g:CreateAnimation("Scale")
	  s1:SetOrder(1)
	  s1:SetDuration(0.10)
	  s1:SetScale(1.08, 1.08)
	  s1:SetSmoothing("OUT")

	  local s2 = g:CreateAnimation("Scale")
	  s2:SetOrder(2)
	  s2:SetDuration(0.18)
	  s2:SetScale(0.93, 0.93)  -- returns near normal (scale is relative per anim)
	  s2:SetSmoothing("IN_OUT")

	  -- Energy “ignite”
	  local aUp = g:CreateAnimation("Alpha")
	  aUp:SetTarget(frame.energy)
	  aUp:SetOrder(1)
	  aUp:SetDuration(0.10)
	  aUp:SetFromAlpha(0.12)
	  aUp:SetToAlpha(0.65)

	  local aDown = g:CreateAnimation("Alpha")
	  aDown:SetTarget(frame.energy)
	  aDown:SetOrder(2)
	  aDown:SetDuration(0.35)
	  aDown:SetFromAlpha(0.65)
	  aDown:SetToAlpha(0.18)

	  -- Runes rotate slightly
	  local rot = g:CreateAnimation("Rotation")
	  rot:SetTarget(frame.runes)
	  rot:SetOrder(1)
	  rot:SetDuration(0.55)
	  rot:SetSmoothing("OUT")
	  rot:SetDegrees(60)

	  return g
	end

	f.procAnim = BuildProcAnim(f)

	SLASH_WFPROC1 = "/wfproc"
	SlashCmdList["WFPROC"] = function()
	  f.procAnim:Stop()
	  f.procAnim:Play()
	end

Type /wfproc in-game to see the center “wake up”. That’s the first milestone ✅

⸻

Open decision: center energy style

Pick one so the Gemini prompts (and assets) stay consistent:
	1.	Air/lightning (blue storm, Windfury vibe) — current prompt above.
	2.	Elemental blend (subtle hints of fire/earth/water/air all around the edge).

Once chosen, tailor the wf_center_energy (and optional glow) prompts to match.

⸻

File + project structure (what the AI must create)

We will keep code modular and testable:

Interface/AddOns/MyTotemWF/
	•	MyTotemWF.toc
	•	Core.lua                (events, saved vars, init)
	•	Media.lua               (one place for all asset paths + design constants)
	•	TotemsUI.lua            (totem bar UI + updates)
	•	WindfuryTracker.lua     (combat log parsing + stats)
	•	WindfuryRadialUI.lua    (radial frames + animations)
	•	SlashCommands.lua       (/wfassets, /wftest, /wftoggle, etc.)
	•	AssetTest.lua           (standalone visual tester for textures)
	•	Media/
	•	wf_center_bg.tga, wf_center_border.tga, wf_center_runes.tga, wf_center_energy.tga (512×512, center ring kit)
	•	orb_bg.tga, orb_border.tga, glow_soft.tga, ring_runes.tga (satellites / legacy; sizes per “Asset pipeline”)
	•	font.ttf (optional)
	•	LICENSE.txt (if using CC0 assets)

The TOC must list files in the correct load order (Media.lua early, then modules).

The “AssetTest.lua” exists so you can verify textures load correctly without any other code running. This prevents chasing ghosts.

⸻

Important: where does this add-on live on disk?

In Classic/TBC clients, add-ons still load from Interface/AddOns/.... What’s different in 2026 is that TBC Anniversary appears to be a separate client/install for many players, so the AddOns folder you need might not be the one you used last week.  ￼

So the dev AI must assume:
	•	You may need to copy the addon folder into the TBC Anniversary install’s Interface/AddOns/ location, not Classic Era’s.  ￼

⸻

Asset sourcing: what you can legally use (super important)

You cannot just rip OPie’s art. OPie’s page lists its license as “All Rights Reserved,” so copying its textures is not okay.

What you can do:
	•	Create your own textures (best)
	•	Use CC0/public-domain packs and modify them
	•	Buy an asset pack with redistribution rights

A safe, easy CC0 source:
	•	Kenney UI Pack is explicitly CC0 and allowed for any project, redistribution included.  ￼

What we do in practice:
	•	Download a CC0 pack, grab a few base shapes (rings/panels), then modify them into our “orb/rune” style.
	•	Save a LICENSE.txt with the license reference if needed (good hygiene even with CC0).

⸻

Technical rules for WoW textures (so they actually load)

WoW UI textures should be BLP or TGA. If paths or formats are wrong you often get “green”/invalid textures.  ￼

Key rules:
	•	Use .TGA or .BLP (not PNG/JPG)  ￼
	•	Use 24-bit RGB or 32-bit RGBA (alpha) — 8-bit/16-bit often fails  ￼
	•	Use power-of-two dimensions (128/256/512…), up to 1024  ￼

Practical recommendation:
	•	Use uncompressed 32-bit TGA with alpha for simplicity (your glow/runes need alpha).

⸻

Asset pipeline (what YOU do once, then the AI can develop)

Step 1: Decide the “theme”
Pick one of these so the AI designs consistent visuals:
	•	“Blizzard-adjacent bronze/stone” (warrior-ish, classic UI vibe)
	•	“Air/Arcane blue glass” (Windfury vibe, still WoW-ish)
	•	See also “Open decision: center energy style” (air/lightning vs elemental blend).

Step 2a: Center ring kit (first milestone) — 4 textures, 512×512
	•	wf_center_bg.tga, wf_center_border.tga, wf_center_runes.tga, wf_center_energy.tga
	•	Use the Gemini prompts and GIMP workflow in “Center ring kit” and “Gemini prompts” above.
	•	Optional later: wf_center_glow_soft.tga for extra bloom.

Step 2b: Satellite / totem kit (orb set)
	•	orb_bg.tga (128×128), orb_border.tga (128×128), glow_soft.tga (256×256), ring_runes.tga (512×512)
	•	Dark radial gradient, ring, soft glow, faint runic ring — used for stat orbs and totem bar.

Step 3: Convert/export correctly
	•	Export as 32-bit TGA with alpha, power-of-two sizes.  ￼
	•	Put into Media/ folder inside the add-on.

Step 4: Add a “Media.lua” file
One place for all asset paths + constants (scale, font sizes, colors). Include both center ring (wf_center_*) and orb set (orb_*, glow_soft, ring_runes).

⸻

How the code loads assets (exact pattern we use everywhere)

In Media.lua:

local ADDON = ...
local M = {}

M.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\"

M.TEX = {
  -- Center ring (512×512, layered)
  CENTER_BG     = M.MEDIA .. "wf_center_bg.tga",
  CENTER_BORDER = M.MEDIA .. "wf_center_border.tga",
  CENTER_RUNES  = M.MEDIA .. "wf_center_runes.tga",
  CENTER_ENERGY = M.MEDIA .. "wf_center_energy.tga",
  -- Orb set (satellites / totems)
  ORB_BG     = M.MEDIA .. "orb_bg.tga",
  ORB_BORDER = M.MEDIA .. "orb_border.tga",
  GLOW       = M.MEDIA .. "glow_soft.tga",
  RING_RUNES = M.MEDIA .. "ring_runes.tga",
}

M.FONT = {
  MAIN = M.MEDIA .. "font.ttf", -- optional
}

return M

Then any UI file does:

local ADDON = ...
local M = select(2, ...) -- or however you structure your addon module passing

(Your dev AI can choose the exact module pattern. The key is: NO hardcoding paths all over the place.)

Texture loading is done via SetTexture(path) and expects TGA/BLP formats and power-of-two sizes.  ￼

⸻

YES: you can build a standalone asset test file (recommended)

This is how you avoid 2 hours of debugging just because one filename is wrong.

AssetTest.lua will:
	•	Create a frame with 4 previews (orb bg, border, glow, runes)
	•	Provide /wfassets to toggle it
	•	Print the resolved paths to chat

When it fails:
	•	wrong path or invalid file format usually shows a very obvious bad result (often “green texture” symptoms are discussed by devs).  ￼

⸻

Windfury tracking: how we detect procs + build stats

We listen to:
	•	COMBAT_LOG_EVENT_UNFILTERED

Then call:
	•	CombatLogGetCurrentEventInfo()

We care about subevents like:
	•	SPELL_EXTRA_ATTACKS (common signal used for Windfury-style extra attacks; you’ll see WA authors key off this)  ￼

Basic logic:
	1.	When SPELL_EXTRA_ATTACKS happens from player GUID:
	•	increment proc count
	•	record timestamp “procStartTime”
	•	record “extraAttacks = N” (payload depends on client)
	•	mark state = “expecting windfury damage events now”
	2.	For the next short window (example: 0.40 sec) capture the next 1–2 melee damage events from the player:
	•	sum them for this proc instance
	•	update min/avg/max
	•	update “lastProcTotal”
	•	trigger the radial UI animation

This correlation window matters because combat log lines are separate and you need to associate them to the proc.

Also: to understand combat log arguments reliably, remember “COMBAT_LOG_EVENT_UNFILTERED” gives you a base set of arguments plus extra fields per event type.  ￼

If anything is uncertain, the most “source of truth” approach is to inspect the official in-game API documentation via /api and print the event payload you see in your client.  ￼

⸻

Radial UI implementation (frames + animation groups)

We build:
	•	A parent container frame (hidden by default)
	•	Center ring: 4 stacked textures (bg → energy → border → runes) + FontStrings (“Windfury!”, “TOTAL: …”). Use proc pulse animation (~0.8s) on proc: energy alpha + scale breath + rune rotation. See “WoW code: render the center ring” and “Proc animation” above.
	•	6 satellite orbs (Frame + textures + text), initially stacked at center and hidden
	•	Optional rune ring texture behind it all (or use center runes only)

We animate using AnimationGroups:
	•	CreateAnimationGroup()
	•	group:CreateAnimation("Alpha" | "Scale" | "Translation" | "Rotation")  ￼
	•	Use smoothing for “snappy but clean” motion:
	•	anim:SetSmoothing("OUT") or "IN_OUT"  ￼
	•	Rotation degrees:
	•	Rotation:SetDegrees(angle)  ￼
	•	Optional direct texture rotation:
	•	TextureBase:SetRotation(radians) (if you want manual control)  ￼

The “feel” recipe (timings that usually feel good)
	•	Center pop-in: 0.12–0.16 sec scale + alpha
	•	Rune rotation: 0.55–0.70 sec, subtle alpha (0.15–0.30)
	•	Satellites: start delay stagger of 0.03 sec each, translation duration ~0.18 sec
	•	Hold time: 2.5–3.0 sec
	•	Close: 0.15–0.22 sec collapse + fade

⸻

“Make it feel WoW” styling rules (the non-negotiables)

This is how we keep it from looking like a random web widget:
	•	Use ONE border texture style everywhere (totems + radial)
	•	Use ONE background texture style everywhere
	•	Use ONE font (either GameFontNormal or your shipped font) for all text
	•	Keep text short:
	•	“PROC%”
	•	“MAX”
	•	“AVG”
	•	“MIN”
	•	“PROCS”
	•	Keep numbers aligned and readable (don’t do tiny decimals everywhere)

And keep the proc popup from being “noisy”:
	•	No rainbow
	•	No huge opacity
	•	Only one accent color (wind/air blue) for the proc glow

⸻

Testing plan (so you and the AI don’t get stuck)

Phase 1: Asset loading
	•	Install addon
	•	/reload
	•	/wfassets
	•	Confirm center ring textures (wf_center_*) and orb set display correctly
If not:
	•	check filename exactness
	•	check format: TGA/BLP only  ￼
	•	check 32-bit alpha
	•	check power-of-two sizes  ￼

Phase 1b: Center ring + proc pulse
	•	/wfproc triggers the center “proc pulse” (glow + breathe + rune rotation) without combat
	•	Confirm center layers stack correctly and animation feels “dead → alive”

Phase 2: Animation sanity
	•	/wftest triggers the full radial animation without combat log
	•	Confirm it opens, rotates, satellites spread, then closes

Phase 3: Combat log detection
	•	Print debug lines when SPELL_EXTRA_ATTACKS fires
	•	Confirm it fires on real Windfury procs in your client
	•	Confirm damage attribution window catches the right swings

Phase 4: Real fight behavior
	•	Stats update across a session
	•	Reset stats on demand
	•	Optional: reset when entering a new instance/zone/combat start

⸻

Performance and safety rules
	•	Create frames once, reuse them (no creating/destroying on every proc)
	•	Avoid heavy string formatting or tables inside the combat log handler
	•	Throttle UI updates (combat log is spammy)
	•	Keep saved variables small: store aggregated stats, not every proc history (unless you want an optional “history mode”)


# Publishing ShammyTime on CurseForge

This guide summarizes what you need to do to publish ShammyTime on CurseForge, based on CurseForge’s official submission guide, [Moderation Policies](https://support.curseforge.com/support/solutions/articles/9000197279-moderation-policies), and “How to Pass Moderation Review” (2025).

---

## Readiness: What you have vs what you need

| Requirement (per moderation) | Status |
|-----------------------------|--------|
| **Name** — English, no game/version in name | ✅ **ShammyTime** is good |
| **Summary** — One line, what it does, English | ✅ Copy from below or adapt from README |
| **Description** — Functional info + what it adds/changes, English first | ✅ Use README content; add **in-game screenshot(s)** |
| **Avatar** — 400×400 px, not solid color, your own, no copyright | ❌ **You need to create/upload** — none in repo |
| **License** — Pick from CurseForge dropdown | ✅ e.g. MIT (matches README) |
| **Categories** — Correct game, main + optional | ✅ Set on project page |
| **File** — .zip, addon folder as root, no external download links | ✅ Zip `ShammyTime/` with .toc + .lua (see §3) |
| **In-game image** — Visual/UI mods need at least one screenshot | ❌ **You need to add** to description or gallery |
| **No third-party downloads** — All files from CurseForge | ✅ No external file links in description |
| **Donation/social links** — Only at bottom, small | ✅ Keep below main description if used |

**Still to do before submit:** (1) Create a **400×400 project avatar** (not solid color; PNG/JPG, avoid WebP). (2) Take **at least one in-game screenshot** of the addon and add it to the project description (or gallery). (3) Create the **.zip** and upload. (4) Fill in Summary, Description, License, Categories on the project page.

---

## 1. CurseForge account and project creation

- Log in at [curseforge.com](https://www.curseforge.com) (or create an account).
- Go to **Create Project** and select **World of Warcraft**.
- Choose the correct **game category** (e.g. **Classic** or the category that matches TBC Anniversary so users can filter by game flavor).

---

## 2. Project page requirements (must pass moderation)

### Name

- **ShammyTime** is fine: unique, short, no version numbers or words like “Addon”/“Mod”.
- Do **not** put version (e.g. “1.0”), game name, or category in the title.

### Summary (one short line)

- Per [moderation policies](https://support.curseforge.com/support/solutions/articles/9000197279-moderation-policies): like a tldr; one sentence, high-level. Don’t copy the description verbatim.
- Example: *“Totem bar with timers, red overlay when too far from totem, Lightning Shield, weapon imbue, and Windfury stats for TBC Anniversary shaman.”*
- Avoid generic lines like “A shaman addon.” Be specific.

### Description (main text)

- Per moderation: **Clear and Informative Description** — must say what the project adds or changes; can include storytelling but must include **functional information**. Avoid generic phrases like “changes the core game” without specifics.
- Use your **README.md** as the base: totems, timers, “gone” feedback, red overlay (too far from totem), Lightning Shield, weapon imbue, Windfury stats and popup, movable/lockable.
- **Include at least one in-game screenshot** (or a couple) showing the addon in use. Visual/UI mods are expected to show accurate in-game representation; this helps moderation and users.
- Use normal capitalization; avoid walls of text and ALL CAPS.
- **English first**; other languages can follow.
- **Donation/social links** (ko-fi, Patreon, personal site, etc.) must appear **at the bottom**, small and reasonable, so they don’t overwhelm the project info ([moderation policies](https://support.curseforge.com/support/solutions/articles/9000197279-moderation-policies)).

### Avatar (project image)

- Per moderation: **Project Avatar** — 400×400 px, not solid color, nothing NSFW or copyrighted. **Avoid WebP** (known bug on CurseForge); use PNG or JPG.
- Must be **your own** (no copyrighted art, no other project’s avatar).
- Can include the name “ShammyTime” or a simple icon; simple is OK.

### License

- Pick a license from the CurseForge dropdown (e.g. **MIT**, **All Rights Reserved**, **GPL**, etc.).
- Your README says “Use and modify as you like. No warranty” — **MIT** or **BSD-3-Clause** matches that; **All Rights Reserved** is also fine if you prefer.

### Categories

- Set the **main category** that best fits (e.g. **Combat**, **Buffs & Debuffs**, **Class**).
- Add up to **5 other categories** if relevant so people can find the addon by filter.

### Optional but recommended

- **Enable comments** so users can report bugs and ask questions (or link to Discord/GitHub in the description).
- **Images**: Add a few gallery screenshots so the addon is easy to understand at a glance.

---

## 3. File submission (WoW addon)

- **Format:** Upload a **.zip** file (not .rar, not .7z, not a renamed archive).
- **Max size:** 2 GB (ShammyTime will be tiny).
- **Structure:** The zip must contain your addon **folder** so that after extraction users get:
  - `ShammyTime/`
    - `ShammyTime.toc`
    - `ShammyTime.lua`
    - (optional) `README.md`, `WOW_UI_STYLING.md`, `CURSEFORGE.md`)
  - Zip the **ShammyTime** folder so the root of the zip is that folder (i.e. path inside zip is `ShammyTime/ShammyTime.toc`, `ShammyTime/ShammyTime.lua`). Do **not** zip the parent `AddOns` folder.
- **Do not** zip your whole `Interface\AddOns` folder; only the single addon folder.
- You need **at least one file** (this zip) before you submit for moderation.

---

## 4. What moderation checks (and what they don’t)

- **Content and policy:** Description clear and appropriate, no NSFW/copyright/offensive content, no misleading AI images without disclosure, follows [CurseForge Moderation Policies](https://support.curseforge.com/en/support/solutions/articles/9000197279-moderation-policies).
- **Project page:** Name, summary, description, avatar, license, and categories as above.
- **Files:** Correct game, valid zip, no external download links in the description that replace the CurseForge file.
- **Code:** CurseForge does **not** publish a formal “code quality” checklist. They don’t automatically scan your Lua for style. They do expect:
  - The addon to **work** and not be malicious.
  - The project to **follow Blizzard’s addon policy** (no selling the addon, no abusive behavior, etc.).

So: **code quality** is not something CurseForge grades line-by-line; what matters is that the addon is functional, honest in the description, and compliant with Blizzard and CurseForge rules.

---

## 5. Code quality (good practice for addons)

These are **community/Blizzard best practices**, not CurseForge requirements. Following them helps stability and compatibility:

- **Locals:** Prefer `local` variables (and local refs to globals in hot paths) to avoid globals and conflicts.
- **Events:** Use the arguments passed to event handlers (e.g. `frame, event, arg1`) instead of relying on global `event`/`arg1`.
- **Hooks:** Prefer `hooksecurefunc` when you only need to run after a Blizzard function; avoid replacing functions if possible.
- **Performance:** Avoid creating throwaway tables in loops or OnUpdate; reuse where possible.
- **Taint:** Avoid tainting the default UI (e.g. don’t hook in a way that breaks SecureHandlers).
- **SavedVariables:** Declare only what you need in the .toc (e.g. `ShammyTimeDB`).

Your ShammyTime code already uses locals, event args, BackdropTemplate, and SavedVariables in a sensible way; no special “CurseForge-only” code is required.

---

## 6. Blizzard addon policy (relevant for “quality”)

- Addons must be **free**; no paywall for the addon itself.
- No **malware** or harmful behavior.
- No **mass data pulls** or excessive API use that could harm the client or servers.

ShammyTime is a simple UI/combat helper and doesn’t touch any of that.

---

## 7. Checklist before you submit

- [ ] CurseForge project created for **World of Warcraft**, correct **category** (e.g. Classic/TBC Anniversary).
- [ ] **Name:** ShammyTime (no version/game name in name — [moderation](https://support.curseforge.com/support/solutions/articles/9000197279-moderation-policies)).
- [ ] **Summary:** One line, what it does, in English (not a copy of the description).
- [ ] **Description:** Clear functional info + what it adds/changes; **at least one in-game screenshot**; English first; donation/socials only at bottom, small.
- [ ] **Avatar:** 400×400 px, PNG or JPG (avoid WebP), not solid color, your own art.
- [ ] **License** selected (e.g. MIT).
- [ ] **.zip** contains only the addon folder as root (e.g. `ShammyTime/ShammyTime.toc`, `ShammyTime/ShammyTime.lua`). No external download links.
- [ ] **Comments** enabled or link to Discord/GitHub for support (recommended by CurseForge).
- [ ] Addon tested in-game and loads without errors.
- [ ] **ShammyTime.toc** `## Version:` matches the file you’re uploading (e.g. 1.0.0).

---

## 8. After submission

- Moderation often runs **Sunday–Thursday, ~8:00–15:00 CET**; files are processed in order.
- If changes are requested or the project is rejected, you’ll get a message (e.g. in notifications). Per [moderation policies](https://support.curseforge.com/support/solutions/articles/9000197279-moderation-policies): **do not delete the project or file and re-upload** — it only complicates things. Edit the same project and/or upload a new file version; you can appeal or ask for clarification via a ticket.
- Disagreements or questions: open a [support ticket](https://support.curseforge.com/en/support/tickets/new).

---

## 9. Useful links

- [CurseForge – Moderation policies](https://support.curseforge.com/support/solutions/articles/9000197279-moderation-policies) (required reading)
- [CurseForge – Project submission guide and tips](https://support.curseforge.com/en/support/solutions/articles/9000199552-project-submission-guide-and-tips)
- [How to pass moderation review (CurseForge blog)](https://blog.curseforge.com/how-to-pass-moderation-review-on-curseforge-2)
- [WoW addons – FAQ and troubleshooting](https://support.curseforge.com/en/support/solutions/articles/9000198422-world-of-warcraft-addons-faq-and-troubleshooting)
- [Creating and submitting a project](https://support.curseforge.com/en/support/solutions/articles/9000197241-creating-and-submitting-a-project)

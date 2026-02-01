# Publishing ShammyTime on CurseForge

This guide summarizes what you need to do to publish ShammyTime on CurseForge, based on CurseForge’s official submission guide, moderation policies, and “How to Pass Moderation Review” (2025).

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

- Shown in search; describe **what it does**, not who made it or for which patch.
- Example: *“Totem bar with timers, red overlay when too far from totem, Lightning Shield and weapon imbue for TBC Anniversary shaman.”*
- Avoid generic lines like “A shaman addon.” Be specific.

### Description (main text)

- Explain **main features and what makes it useful** (totems, timers, “gone” animation, red overlay when too far from totem, Lightning Shield, weapon imbue, movable/lockable).
- **Include at least one in-game screenshot** (or a couple) showing the addon in use. Descriptions that clearly show the addon tend to pass faster.
- Use normal capitalization; avoid walls of text and ALL CAPS.
- **English first**; other languages can follow.
- If you add donation/social links, put them **below** the main description and keep them small.

### Avatar (project image)

- **Minimum 400×400 px**, 1:1.
- Must **not** be a single solid color or a simple gradient.
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
- [ ] **Name:** ShammyTime (no version/category in name).
- [ ] **Summary:** One line, what it does, in English.
- [ ] **Description:** Features, screenshots, English first; donation/socials at bottom if any.
- [ ] **Avatar:** 400×400+, not solid color, your own art.
- [ ] **License** selected.
- [ ] **.zip** contains the addon folder (e.g. `ShammyTime/` with `.toc` and `.lua` inside).
- [ ] **Comments** enabled (or link to Discord/GitHub for support).
- [ ] You’ve tested the addon in-game and it loads without errors.
- [ ] **ShammyTime.toc** `## Version:` matches the release you’re uploading (e.g. 1.0.0).

---

## 8. After submission

- Moderation often runs **Sunday–Thursday, ~8:00–15:00 CET**; files are processed in order.
- If changes are requested, you’ll get a message (e.g. in notifications); **don’t delete the project and re-upload** — edit the same project and/or upload a new file version.
- Disagreements or questions: open a [support ticket](https://support.curseforge.com/en/support/tickets/new).

---

## 9. Useful links

- [CurseForge – Project submission guide and tips](https://support.curseforge.com/en/support/solutions/articles/9000199552-project-submission-guide-and-tips)
- [CurseForge – Moderation policies](https://support.curseforge.com/en/support/solutions/articles/9000197279-moderation-policies)
- [How to pass moderation review (CurseForge blog)](https://blog.curseforge.com/how-to-pass-moderation-review-on-curseforge-2)
- [WoW addons – FAQ and troubleshooting](https://support.curseforge.com/en/support/solutions/articles/9000198422-world-of-warcraft-addons-faq-and-troubleshooting)
- [Creating and submitting a project](https://support.curseforge.com/en/support/solutions/articles/9000197241-creating-and-submitting-a-project)

# Making WoW Addons Look Native (UI Styling Guide)

Tips so your addon fits the game’s look and behaves like the default UI.

---

## 1. Use Blizzard’s Built‑In Textures

Avoid generic solid rectangles when you can. Use the same assets the default UI uses.

### Backdrops (frames and borders)

**Dialog / panel look (dark, bordered):**
```lua
local f = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
f:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
})
f:SetBackdropColor(1, 1, 1, 1)   -- tint; (1,1,1,1) = texture as-is
f:SetBackdropBorderColor(1, 1, 1, 1)
```

**Flat, minimal (like some modern addons):**
```lua
f:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\ChatFrame\\ChatFrameBackground",
    tile = true,
    tileSize = 16,
    edgeSize = 2,
})
f:SetBackdropColor(0.1, 0.1, 0.1, 0.85)
f:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
```

**Solid color with thin border (no custom art):**
- `Interface\\Buttons\\WHITE8x8` for both `bgFile` and `edgeFile`, then use `SetBackdropColor` / `SetBackdropBorderColor` for colors.

### Texture path rules

- Use backslashes: `Interface\\Folder\\TextureName` (no file extension).
- Many textures live under `Interface\\` (e.g. `DialogFrame`, `Tooltips`, `Buttons`, `ChatFrame`).
- For more paths, check Blizzard’s FrameXML/art or community repos (e.g. [wow-ui-textures](https://github.com/Gethe/wow-ui-textures), [BlizzardInterfaceResources](https://github.com/Resike/BlizzardInterfaceResources)).

---

## 2. Use WoW’s Fonts

Stick to the built‑in font objects so size and style match the rest of the UI:

| Font object             | Typical use        |
|-------------------------|--------------------|
| `GameFontNormal`        | Body text, titles  |
| `GameFontNormalSmall`   | Secondary text     |
| `GameFontHighlight`     | Highlighted text   |
| `GameFontDisable`       | Disabled/gray text |
| `NumberFontNormal`      | Numbers            |

Example:
```lua
local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
label:SetTextColor(0.9, 0.9, 0.9)
```

Avoid arbitrary `SetFont()` with system paths unless you intentionally want a different look.

---

## 3. BackdropTemplate and Layering

- **BackdropTemplate:** Always pass `"BackdropTemplate"` when creating frames that use `SetBackdrop`:
  ```lua
  CreateFrame("Frame", nil, parent, "BackdropTemplate")
  ```
- **frameStrata** (e.g. `"DIALOG"`, `"FULLSCREEN_DIALOG"`, `"TOOLTIP"`): Chooses which “layer” of the UI your frame sits on.
- **frameLevel:** Order within that stratum (higher = on top). Use for overlapping elements (e.g. overlays above icons).

---

## 4. Colors That Match the Default UI

- **Panels:** Dark, slightly transparent (e.g. `0.05–0.15` RGB, alpha `0.8–0.95`).
- **Borders:** Slightly lighter gray or gold (e.g. `0.35–0.5` or Blizzard’s brown/gold).
- **Text:** Light gray or white for primary (`0.9–1.0`), dimmer for secondary (`0.6–0.7`).
- **Highlights:** Subtle; avoid bright neon so it doesn’t clash with the rest of the screen.

---

## 5. Code and Structure (Best Practices)

- Prefer **local variables** (and local references to globals in hot paths) for performance and to avoid name clashes.
- In **event handlers**, use the arguments passed to the function (e.g. `frame, event, ...`) instead of globals like `event`, `arg1`.
- **Hooking:** Prefer `hooksecurefunc` when you only need to run code after a Blizzard function; avoid replacing functions if you can.
- **Backdrops:** Reuse the same backdrop table where possible instead of creating new ones every frame to reduce garbage.

---

## 6. Optional: XML for Complex Layouts

For many frames and nested layout, Blizzard uses **FrameXML** (XML + Lua). You can do the same:

- Define frames, textures, and font strings in `.xml` with the WoW Widget API.
- Keep logic and behavior in `.lua`.
- Use the same texture paths, font objects, and strata/levels as above so the result still looks native.

---

## Quick reference: texture paths

| Purpose        | Path |
|----------------|------|
| Dialog bg      | `Interface\\DialogFrame\\UI-DialogBox-Background-Dark` |
| Tooltip border | `Interface\\Tooltips\\UI-Tooltip-Border` |
| Flat bg/border | `Interface\\ChatFrame\\ChatFrameBackground` |
| Solid color    | `Interface\\Buttons\\WHITE8x8` |
| Icons          | `Interface\\Icons\\...` (e.g. `INV_Elemental_Primal_Fire`) |

Using these consistently will make your addon look and feel like part of the default WoW UI.

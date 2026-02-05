Do now: 
- [x] Increase size of small text elements such as totem timers, and text sizes in all bubbles. How ever do not change the current default, but add sizing options in the ingame cmd so ppl can set their own sizes per artwork thingie.
- [x] Increase metrics bubble sizes and reduce WF bubble size so the center bubble is 20% larger than the smaller bubbles, but make everything relatively more equal than it is today, and spread the small bubbles around the center circle equally having 3 on each side so there is not an empty spot on the bottom.
- [x] Implement lightning and water shield indicator (off/on overlay with alpha fade + orb count 0–3 for Lightning/Water Shield). 

- [x] improve the cmd line interface settings in game so its easy for users to understand and use. Separate between simple settings and advanced settings such as text and positional changes. Simple settings should be enable fade mode on or off with current default settings. And turn on or off elements one by one if they are not wanted. And resizing the elements as a whole / scaling. All other settings should be placed into advanced. And the simple settings should be accessible through /st fade /st scale n, and so on. For advanced it should be /st adv x y z options where there is a clear hierarchical struture for each element like totembar, windfury bubbles, shield, etcetc and for each one of those they should have subcategories and settings in a clean and clear way with clear descriptions of what is going on so the user understands whats going on. /st test can be used also to show the functionality. 

- [x] when it comes to printing the positions of the elements and being able to move them ingame we need to have the current offset be shown in the /print statement so i can move things around and understand at what position it looks good and then we can use that as defaults in the code. In order to do that i must understand what offset all of the elements have currently or overridden.

**Ace3 Options Panel:**
- `/st options` opens the settings panel
- `/st dev on` enables the Developer tab for text position adjustments
- `/st print` exports all settings to chat for copy/paste

**Text Position Workflow (Developer Mode):**
1. Run `/st dev on` to show Developer tab
2. Run `/st test` to show all elements
3. Open settings panel with `/st options`
4. Go to Developer tab and adjust text positions for each bubble
5. Run `/st print` to export settings
6. Copy the output and paste it here so defaults can be updated in code

- [x] Ensure that the scaling options for the bubbles/circles windfury element scale properly together. Example of how to do it: Create a single parent container frame for the circle + bubble and only scale/resize the parent (not the textures individually). Make the circle fill the container. Position the bubble by anchoring its CENTER to the container CENTER with offsets computed from sizes: distance = circleRadius + bubbleRadius (circleRadius = min(containerW,containerH)/2, bubbleRadius = min(bubbleW,bubbleH)/2). Use x = distance*cos(angle), y = distance*sin(angle) (or fixed directions like right/top). Recalculate on size/scale changes so the bubble always stays touching the circle edge.

- [x] Make sure that for each element the scaling ensures that the Elements stay in place and that the text is increased properly and not scaled in such a way that it will pixelate be beneath. You can find GPT's example of how to do this
Got it 🙂 Keep it simple: one slider-ish scale (+/- ~30%), same assets, and absolutely no drifting.

Here are instructions you can paste to your dev AI:
	1.	Create ONE “root” frame that represents the entire widget (circle + bubble + text). Anchor ONLY this root to UIParent once (typically CENTER). Never anchor individual elements to UIParent.
	2.	Parent every element (textures + fontstrings + subframes) to this root frame. All SetPoint() calls for children must be relative to root (or other children inside root), never UIParent.
	3.	Apply scaling ONLY at the root frame level: root:SetScale(scaleFactor) where scaleFactor is e.g. 0.7 to 1.3. Do NOT call SetScale() on any child element. Do NOT change any child SetPoint() offsets when scaling.
	4.	Before setting any anchors, always do child:ClearAllPoints() so you don’t accidentally leave multiple anchors active.
	5.	For the bubble that must stay touching the circle: don’t hardcode pixel offsets. Compute bubble position from radii so it remains correct at any scale:
	•	circle radius = min(rootWidth, rootHeight) / 2
	•	bubble radius = min(bubbleWidth, bubbleHeight) / 2
	•	distance between centers = circleR + bubbleR
	•	offsets = x = distance*cos(angle), y = distance*sin(angle)
Then bubble:SetPoint("CENTER", root, "CENTER", x, y).
This should be calculated once after sizes are set; scaling the root will preserve the relationship.
	6.	Avoid mixing “resize” and “scale” for this feature. Pick scale only:
	•	root has a fixed base size (e.g. 128x128)
	•	you only change root:SetScale(s)
This guarantees positions don’t drift because anchors and offsets scale together.
	7.	Debug checklist if drifting still happens:
	•	Confirm no child is anchored to UIParent.
	•	Confirm no child is being re-SetPoint’d on scale changes.
	•	Confirm only root has SetScale changed (children scale = 1).
	•	Confirm ClearAllPoints() is used before anchoring.
	•	Confirm bubble and circle share the same parent (root).

That’s it: a single anchored root + scale root only + bubble position derived from sizes = everything grows/shrinks in place without sliding around.

- [x] Clicking the stop demo button moves assets around, specifically the totem bar. The demo buttons should not affect any thing besides starting or stopping the animations.

Info from GPT: Totally. This is almost always happening because the “stop demo” code is accidentally touching layout state (anchors, size, scale, alpha, strata, parent, or a shared table of positions). The fix is to hard-separate “animation state” from “layout state” ✅

Paste this to your dev AI as the task/spec:
	•	The “Stop Demo” button must only stop demo animations and timers. It must not call any layout or placement functions and must not change any frame’s anchors, size, scale, parent, strata/level, or points.
	•	Specifically: do not call any function that runs ClearAllPoints(), SetPoint(), SetSize(), SetScale(), SetParent(), SetFrameStrata(), SetFrameLevel(), SetAllPoints(), or any “RefreshUI / ApplyLayout / RebuildFrames” type function from the stop-demo path.
	•	Stop demo must do only:
	1.	animGroup:Stop() (or equivalent)
	2.	cancel any timers / C_Timer / AceTimer handles created by demo
	3.	reset animation-only properties if needed (e.g. alpha back to normal) BUT do not move anything
	•	If any visual properties were changed by demo (alpha, vertex color, desaturation), restore them from cached “pre-demo” values, not by re-applying layout. Cache those values once when demo starts.
	•	Ensure demo uses its own animation objects (AnimationGroup) and never updates positions by repeatedly calling SetPoint() during the animation. If you need movement in demo, animate via translation (AnimationGroup) rather than re-anchoring.
	•	Ensure the totem bar frame is not being re-parented to a “demo container” and back. Demo should act on the same frames in-place.

Quick debugging instruction:
	•	Add a temporary wrapper/log around SetPoint for the totem bar frame; click Stop Demo; if SetPoint fires, you found the bug path. Also grep the Stop Demo handler for ClearAllPoints/SetPoint/ApplyLayout/UpdatePositions.

Expected behavior:
	•	Clicking Stop Demo should leave all frames exactly where they were (same anchors/offsets). Only animation playback stops and visuals return to their normal non-demo state.


- [x] When the shamanistic focus is enabled when coming from its faded state the change from the off the off picture to the own picture is too slow. It needs to be quicker I wanted to roughly take 300 ms.

- [x] Remove all preview buttons in each module. Its enough with the one in general.

- [x] The fade in option when you have a target should slowly fade in the windfury bubbles when you select an enemy. So two things: Slow fade in, and enemy target only. BUT very impotant when this option is not enabled the windfury bubbles should not fade in, but appear instantly like the current behavior.

- [x] The fade in option when you have a target should slowly fade in the shamanistic focus when you select an enemy. So two things: Slow fade in, and enemy target only.

- [x] The windfury bubbles does not fade out when the "no active buff/pric is enabled. Bug. 

- [x] The shamanistic focus is affected by settings when i change windfury bubbles settings. Bug. 



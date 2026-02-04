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
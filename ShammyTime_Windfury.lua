-- ShammyTime_Windfury.lua
-- Windfury proc detection (SPELL_EXTRA_ATTACKS + damage correlation window) and ShowRadial (center ring + satellites).
-- WoW Classic TBC Anniversary 2026; compatible with 20501–20505.

local addonName = ...
if addonName ~= "ShammyTime" then return end

local M = ShammyTime_Media
if not M then return end

local WF_WINDOW = M.WF_CORRELATION_WINDOW
local WINDFURY_ATTACK_SPELL_ID = 25584

local wfExpectingDamage = false
local wfWindowTotal = 0
local wfWindowHits = 0
local wfWindowTimer = nil
local wfRadialShownForThisProc = false  -- true once we've shown the radial for this proc (to avoid replaying animation)

-- Clear any in-flight Windfury proc window (used on stats reset)
function ShammyTime.ResetWindfuryProcWindow()
    if wfWindowTimer then
        wfWindowTimer:Cancel()
        wfWindowTimer = nil
    end
    wfExpectingDamage = false
    wfWindowTotal = 0
    wfWindowHits = 0
    wfRadialShownForThisProc = false
end

local function GetDB()
    return ShammyTime and ShammyTime.GetDB and ShammyTime.GetDB() or {}
end

local function GetStatsForRadial()
    local pull, session, lastTotal = nil, nil, 0
    if ShammyTime and ShammyTime.GetWindfuryStats then
        pull, session, lastTotal = ShammyTime.GetWindfuryStats()
    end
    session = session or {}
    local count = session.count or 0
    local procs = session.procs or 0
    local swings = session.swings or 0
    local crits = session.crits or 0
    local procPct = (swings > 0 and procs > 0) and (procs / swings * 100) or 0
    local critPct = (count > 0 and crits > 0) and (crits / count * 100) or nil
    -- Min/max/avg are per-PROC (combined damage of 1–2 hits per Windfury proc)
    local avg = (procs > 0 and session.total) and math.floor(session.total / procs + 0.5) or nil
    local max = session.max
    if avg and max and avg > max then
        -- Guard against mismatched stats from earlier split-proc flushes.
        max = avg
    end
    return {
        min = session.min,
        max = max,
        avg = avg,
        procPct = procPct,
        procCount = procs,
        critPct = critPct,
        lastTotal = lastTotal,
    }
end

-- Expose stats for the new satellite UI (center + rings)
function ShammyTime_Windfury_GetStats()
    return GetStatsForRadial()
end

-- Called when correlation window ends with a proc total (or from /st test). Uses center ring + satellite rings only.
-- updateOnly: if true, only update the TOTAL text without replaying the animation (used when window closes after instant show)
function ShammyTime_Windfury_ShowRadial(procTotal, updateOnly)
    if ShammyTime.FlushWindfuryProcIfClosed then
        ShammyTime.FlushWindfuryProcIfClosed()
    elseif ShammyTime.FlushWindfuryProc then
        ShammyTime.FlushWindfuryProc()
    end
    if procTotal then
        ShammyTime.lastProcTotal = procTotal
    end
    if updateOnly then
        -- Just update the text, don't replay animation
        if ShammyTime.UpdateCenterRingTotal then
            ShammyTime.UpdateCenterRingTotal(procTotal)
        end
    else
        if ShammyTime.PlayCenterRingProc then
            ShammyTime.PlayCenterRingProc(procTotal)
        end
    end
end

-- Start or extend the proc damage window (called from SPELL_EXTRA_ATTACKS or first WF damage)
-- showInstant: if true, show the radial immediately with current total (for SPELL_EXTRA_ATTACKS)
local function StartProcWindow(showInstant)
    wfExpectingDamage = true
    wfRadialShownForThisProc = false  -- reset for new proc window
    if wfWindowTimer then wfWindowTimer:Cancel() end
    -- Show radial instantly on SPELL_EXTRA_ATTACKS so user sees feedback immediately
    if showInstant then
        ShammyTime_Windfury_ShowRadial(wfWindowTotal)
        wfRadialShownForThisProc = true
    end
    wfWindowTimer = C_Timer.NewTimer(WF_WINDOW, function()
        wfWindowTimer = nil
        wfExpectingDamage = false
        if wfWindowHits > 0 then
            -- If we already showed the radial, just update the text; otherwise play full animation
            ShammyTime_Windfury_ShowRadial(wfWindowTotal, wfRadialShownForThisProc)
        end
        wfRadialShownForThisProc = false
    end)
end

-- Combat log: SPELL_EXTRA_ATTACKS starts window; SPELL_DAMAGE 25584 sums. Fallback: first WF damage starts window if no SPELL_EXTRA_ATTACKS (e.g. Classic).
local function OnCombatLog()
    local db = GetDB()
    if not db.wfRadialEnabled then return end
    if not CombatLogGetCurrentEventInfo then return end

    local subevent = select(2, CombatLogGetCurrentEventInfo())
    if subevent == "SPELL_EXTRA_ATTACKS" then
        local srcGUID = select(4, CombatLogGetCurrentEventInfo())
        if srcGUID == UnitGUID("player") then
            wfWindowTotal = 0
            wfWindowHits = 0
            StartProcWindow(true)  -- showInstant: show radial immediately on proc
        end
        return
    end

    if subevent ~= "SPELL_DAMAGE" and subevent ~= "SPELL_DAMAGE_CRIT" then return end

    local srcGUID = select(4, CombatLogGetCurrentEventInfo())
    if srcGUID ~= UnitGUID("player") then return end
    local spellId = select(12, CombatLogGetCurrentEventInfo())
    local spellName = select(13, CombatLogGetCurrentEventInfo())
    local amount = select(15, CombatLogGetCurrentEventInfo())
    if not amount or amount <= 0 then return end
    local isWindfury = (spellId == WINDFURY_ATTACK_SPELL_ID) or (spellName and spellName == "Windfury Attack")
    if not isWindfury then return end

    -- Fallback: if we didn't get SPELL_EXTRA_ATTACKS (e.g. TBC/Classic), first WF damage starts the window
    if not wfExpectingDamage then
        wfWindowTotal = 0
        wfWindowHits = 0
        StartProcWindow(true)  -- showInstant: show radial immediately on first WF damage
    end

    wfWindowTotal = wfWindowTotal + amount
    wfWindowHits = wfWindowHits + 1
    -- Windfury = up to 2 extra attacks; after 2 hits we can close window early
    if wfWindowHits >= 2 and wfWindowTimer then
        wfWindowTimer:Cancel()
        wfWindowTimer = nil
        wfExpectingDamage = false
        -- If we already showed the radial, just update the text; otherwise play full animation
        ShammyTime_Windfury_ShowRadial(wfWindowTotal, wfRadialShownForThisProc)
        wfRadialShownForThisProc = false
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        OnCombatLog()
    end
end)

-- Global test (/st test) runs in ShammyTime.lua; triggers proc immediately then every 10s.

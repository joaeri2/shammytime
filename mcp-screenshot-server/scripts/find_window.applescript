#!/usr/bin/osascript

-- Find window ID for a given application name
-- Usage: osascript find_window.applescript "World of Warcraft"

on run argv
    if (count of argv) < 1 then
        error "Usage: osascript find_window.applescript <application_name>"
    end if
    
    set appName to item 1 of argv
    
    tell application "System Events"
        if not (exists process appName) then
            error "Application '" & appName & "' is not running"
        end if
        
        tell process appName
            if (count of windows) = 0 then
                error "Application '" & appName & "' has no windows"
            end if
            
            set windowID to id of window 1
            set windowName to name of window 1
            
            -- Return as JSON-like format
            return "{\"id\":" & windowID & ",\"name\":\"" & windowName & "\",\"application\":\"" & appName & "\"}"
        end tell
    end tell
end run

#!/usr/bin/osascript

-- List all windows for a given application (or all applications if no arg)
-- Usage: osascript list_windows.applescript [application_name]

on run argv
    set output to "["
    set firstItem to true
    
    tell application "System Events"
        if (count of argv) > 0 then
            -- List windows for specific application
            set appName to item 1 of argv
            
            if not (exists process appName) then
                return "[]"
            end if
            
            tell process appName
                repeat with w in windows
                    if not firstItem then
                        set output to output & ","
                    end if
                    set firstItem to false
                    
                    set windowID to id of w
                    set windowName to name of w
                    set windowPosition to position of w
                    set windowSize to size of w
                    
                    set output to output & "{\"id\":" & windowID & ",\"name\":\"" & windowName & "\",\"application\":\"" & appName & "\",\"bounds\":{\"x\":" & (item 1 of windowPosition) & ",\"y\":" & (item 2 of windowPosition) & ",\"width\":" & (item 1 of windowSize) & ",\"height\":" & (item 2 of windowSize) & "}}"
                end repeat
            end tell
        else
            -- List windows for all applications
            repeat with proc in processes
                set appName to name of proc
                
                tell proc
                    if (count of windows) > 0 then
                        repeat with w in windows
                            if not firstItem then
                                set output to output & ","
                            end if
                            set firstItem to false
                            
                            set windowID to id of w
                            set windowName to name of w
                            
                            try
                                set windowPosition to position of w
                                set windowSize to size of w
                                set output to output & "{\"id\":" & windowID & ",\"name\":\"" & windowName & "\",\"application\":\"" & appName & "\",\"bounds\":{\"x\":" & (item 1 of windowPosition) & ",\"y\":" & (item 2 of windowPosition) & ",\"width\":" & (item 1 of windowSize) & ",\"height\":" & (item 2 of windowSize) & "}}"
                            on error
                                set output to output & "{\"id\":" & windowID & ",\"name\":\"" & windowName & "\",\"application\":\"" & appName & "\"}"
                            end try
                        end repeat
                    end if
                end tell
            end repeat
        end if
    end tell
    
    set output to output & "]"
    return output
end run

-- PC-056: Real macOS keyboard shortcuts acceptance for Pixel Companion.
-- Run only on an authorized Mac with the menu-bar popover OPEN.
-- Changes selected tab only, never operates a provider.
-- Usage: osascript scripts/quality/verify_live_keyboard.applescript <app_pid>
on run arguments
    if (count of arguments) is not 1 then error "PC056: expected app PID" number 2
    set expectedPID to (item 1 of arguments) as integer
    if expectedPID is less than 1 then error "PC056: invalid PID" number 2

    tell application "System Events"
        if UI elements enabled is false then error "PC056: Accessibility permission required" number 3
        tell process "PixelCompanion"
            if (unix id) is not expectedPID then error "PC056: wrong process PID" number 4
            if (count of pop overs of menu bar 1) is not 1 then error "PC056: open the menu-bar popover first" number 5
            set frontmost to true
        end tell

        repeat with tabNumber from 1 to 4
            keystroke (tabNumber as text) using {command down}
            delay 0.15
            tell process "PixelCompanion"
                if (count of pop overs of menu bar 1) is not 1 then error "PC056: popover closed" number 6
                set selectedCount to 0
                repeat with buttonNumber from 1 to 4
                    set tabButton to button buttonNumber of group 1 of group 1 of pop over 1 of menu bar 1
                    set selectionValue to value of attribute "AXValue" of tabButton
                    if selectionValue is "Selected" then
                        set selectedCount to selectedCount + 1
                        if buttonNumber is not tabNumber then error "PC056: wrong selected tab" number 7
                    else if selectionValue is not "Not selected" then
                        error "PC056: missing selection value" number 8
                    end if
                end repeat
                if selectedCount is not 1 then error "PC056: selected tab count wrong" number 9
            end tell
        end repeat
    end tell
    return "PC056_KEYBOARD_SHORTCUTS: PASS (Cmd-1 to Cmd-4, selected state)"
end run

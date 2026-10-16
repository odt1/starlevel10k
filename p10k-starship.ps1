# Right prompt for Starship in PowerShell.
#
# Starship draws `right_format` in most shells, but its PowerShell setup leaves
# it out. This file adds it. Load it in $PROFILE right after Starship:
#
#     Invoke-Expression (&starship init powershell)
#     . "$HOME\p10k-starship\p10k-starship.ps1"
#
# Every prompt then also asks Starship for the right side (`starship prompt
# --right`, with the same arguments as the left side) and puts it at the right
# edge of the line you type on. As in zsh, the right side is left out when it
# does not fit next to the left side. Unlike zsh, text you type over it
# overwrites it instead of hiding it.

# Starship's setup is a dynamic module, which Get-Module does not list, so
# find it through the prompt function it defines.
$starshipModule = ${function:prompt}.Module
if ($starshipModule.Name -ne 'starship' -or -not (& $starshipModule { Test-Path function:Invoke-Native })) {
    Write-Warning 'p10k-starship.ps1: load this file after "Invoke-Expression (&starship init powershell)".'
    return
}

& $starshipModule {
    # Loading this file twice must not wrap the function twice.
    if ($script:P10kInvokeNative) { return }

    # Starship's own helper that runs starship.exe. The prompt function calls it
    # with all the arguments the prompt needs, so wrapping it is enough.
    $script:P10kInvokeNative = ${function:Invoke-Native}

    # Number of terminal cells $Text takes: escape sequences take none, wide
    # characters (CJK, emoji) take two, everything else one.
    function script:Get-P10kWidth([string]$Text) {
        $plain = $Text -replace '\x1b\[[0-?]*[ -/]*[@-~]|\x1b\][^\a\x1b]*(\a|\x1b\\)', ''
        $width = 0
        $elements = [Globalization.StringInfo]::GetTextElementEnumerator($plain)
        while ($elements.MoveNext()) {
            $element = $elements.GetTextElement()
            $code = [char]::ConvertToUtf32($element, 0)
            $wide = $element.Contains([char]0xFE0F) -or
                ($code -ge 0x1100 -and $code -le 0x115F) -or
                ($code -ge 0x2E80 -and $code -le 0xA4CF) -or
                ($code -ge 0xAC00 -and $code -le 0xD7A3) -or
                ($code -ge 0xF900 -and $code -le 0xFAFF) -or
                ($code -ge 0xFE30 -and $code -le 0xFE4F) -or
                ($code -ge 0xFF00 -and $code -le 0xFF60) -or
                ($code -ge 0xFFE0 -and $code -le 0xFFE6) -or
                ($code -ge 0x1F300 -and $code -le 0x1F64F) -or
                ($code -ge 0x1F900 -and $code -le 0x1F9FF) -or
                ($code -ge 0x20000 -and $code -le 0x3FFFD)
            $width += if ($wide) { 2 } else { 1 }
        }
        $width
    }

    function script:Invoke-Native {
        param($Executable, $Arguments)
        $left = & $script:P10kInvokeNative -Executable $Executable -Arguments $Arguments

        # Only the main prompt has a right side, the continuation prompt does not.
        if (-not $left -or $Arguments[0] -ne 'prompt' -or $Arguments -contains '--continuation') {
            return $left
        }
        $right = & $script:P10kInvokeNative -Executable $Executable -Arguments (@($Arguments) + '--right')
        $rightWidth = Get-P10kWidth $right
        if ($rightWidth -eq 0) {
            return $left
        }

        $start = $left.LastIndexOf("`n") + 1
        $lastLine = $left.Substring($start)
        $terminalWidth = $Host.UI.RawUI.WindowSize.Width
        if ((Get-P10kWidth $lastLine) + 1 + $rightWidth -gt $terminalWidth) {
            return $left
        }

        # Draw the right side at its column first, then go back to the start of
        # the line and draw the left side. The cursor ends up after the left
        # side, which is where PSReadLine expects it.
        $esc = [char]27
        $column = $terminalWidth - $rightWidth + 1
        $left.Substring(0, $start) + "$esc[${column}G" + $right + "`r" + $lastLine
    }
}

Remove-Variable starshipModule

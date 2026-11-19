# Run with Windows PowerShell 5.1 or later. Uses mocks, not the real registry.
$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'uninstall.ps1'
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    $scriptPath, [ref]$tokens, [ref]$errors
) | Out-Null
if ($errors.Count -ne 0) { throw "uninstall.ps1 has syntax errors: $errors" }

& {
    $state = @{ present = $true; removals = 0; checks = 0 }
    $expected = 'HKCU:\Software\Classes\ccnotify-focus'

    function Test-Path {
        [CmdletBinding()]
        param([string]$LiteralPath)
        if ($LiteralPath -cne $expected) { throw "Unexpected registry path: $LiteralPath" }
        $state.checks++
        return $state.present
    }

    function Remove-Item {
        [CmdletBinding()]
        param([string]$LiteralPath, [switch]$Recurse, [switch]$Force)
        if ($LiteralPath -cne $expected) { throw "Unexpected removal path: $LiteralPath" }
        if (-not ($Recurse -and $Force)) { throw "Expected recursive removal" }
        if (-not $state.present) { throw "Tried to remove an absent key" }
        $state.present = $false
        $state.removals++
    }

    $first = & $scriptPath
    if ($state.present -or $state.removals -ne 1 -or $first -notlike 'Removed *') {
        throw "Expected the registered key to be removed once"
    }

    $second = & $scriptPath
    if ($state.removals -ne 1 -or $state.checks -ne 2 -or $second -notlike 'Nothing to remove*') {
        throw "Expected a second run to skip removal"
    }
}

Write-Output 'Uninstall tests passed.'

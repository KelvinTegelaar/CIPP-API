function Get-CIPPBaselineSmartLockoutState {
    <#
    .SYNOPSIS
        Prepare hook for SmartLockout: the password-rule directory setting's lockout values.
    .DESCRIPTION
        Grades the four lockout values on the password rule settings template
        (5cf42378-d67d-4f36-ba46-e8b86229381d). Directory setting values are STRINGS on the
        wire, so both sides grade as strings. A tenant with no password-rule setting object
        grades every value against empty - not configured is drift, and remediation creates
        the object.

        'Enforced' normalizes to 'Enforce' - Graph only accepts Audit/Enforce, and older
        saved baselines carry the misspelling.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Settings = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Settings')
    if ($Settings.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'Settings')) {
        return @{ Current = $null }
    }

    $V = $Item.Variables
    $Duration = "$($V.LockoutDurationInSeconds.value ?? $V.LockoutDurationInSeconds)"
    $Threshold = "$($V.LockoutThreshold.value ?? $V.LockoutThreshold)"
    $OnPrem = if ($V.EnableBannedPasswordCheckOnPremises -eq $true -or "$($V.EnableBannedPasswordCheckOnPremises)" -eq 'True') { 'True' } else { 'False' }
    $Mode = "$($V.BannedPasswordCheckOnPremisesMode.value ?? $V.BannedPasswordCheckOnPremisesMode)"
    if ($Mode -eq 'Enforced') { $Mode = 'Enforce' }
    if ([string]::IsNullOrWhiteSpace($Mode)) { $Mode = 'Audit' }

    $Existing = @($Settings | Where-Object { "$($_.templateId)" -eq '5cf42378-d67d-4f36-ba46-e8b86229381d' }) | Select-Object -First 1
    $ValueOf = { param($Name) "$((@($Existing.values) | Where-Object { $_.name -eq $Name }).value)" }

    $Current = [PSCustomObject]@{
        lockoutDurationInSeconds            = $(if ($Existing) { & $ValueOf 'LockoutDurationInSeconds' } else { '' })
        lockoutThreshold                    = $(if ($Existing) { & $ValueOf 'LockoutThreshold' } else { '' })
        enableBannedPasswordCheckOnPremises = $(if ($Existing) { & $ValueOf 'EnableBannedPasswordCheckOnPremises' } else { '' })
        bannedPasswordCheckOnPremisesMode   = $(if ($Existing) { & $ValueOf 'BannedPasswordCheckOnPremisesMode' } else { '' })
    }
    $Current | Add-Member -NotePropertyName 'settingId' -NotePropertyValue "$($Existing.id)"

    @{
        Expected = [PSCustomObject]@{
            lockoutDurationInSeconds            = $Duration
            lockoutThreshold                    = $Threshold
            enableBannedPasswordCheckOnPremises = $OnPrem
            bannedPasswordCheckOnPremisesMode   = $Mode
        }
        Current  = $Current
    }
}

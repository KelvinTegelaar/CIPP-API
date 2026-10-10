function Get-CIPPBaselineConsentPolicySettingsState {
    <#
    .SYNOPSIS
        Prepare hook for ConsentPolicySettings: the two values on the Consent Policy Settings
        directory setting.
    .DESCRIPTION
        Grades BlockUserConsentForRiskyApps and EnableAdminConsentRequests on the consent
        policy settings template (dffd5d46-495d-40a9-8e21-954ff55e198a). Directory setting
        values are STRINGS on the wire, so both sides grade as lower-case strings. A tenant
        with no consent policy setting object grades every value against empty - not
        configured is drift, and remediation creates the object.
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
    $AsFlag = { param($Value) if ($Value -eq $true -or "$Value" -eq 'True') { 'true' } else { 'false' } }

    $Existing = @($Settings | Where-Object { "$($_.templateId)" -eq 'dffd5d46-495d-40a9-8e21-954ff55e198a' }) | Select-Object -First 1
    $ValueOf = { param($Name) "$((@($Existing.values) | Where-Object { $_.name -eq $Name }).value)".ToLower() }

    $Current = [PSCustomObject]@{
        blockUserConsentForRiskyApps = $(if ($Existing) { & $ValueOf 'BlockUserConsentForRiskyApps' } else { '' })
        enableAdminConsentRequests   = $(if ($Existing) { & $ValueOf 'EnableAdminConsentRequests' } else { '' })
    }
    $Current | Add-Member -NotePropertyName 'settingId' -NotePropertyValue "$($Existing.id)"

    @{
        Expected = [PSCustomObject]@{
            blockUserConsentForRiskyApps = & $AsFlag $V.BlockUserConsentForRiskyApps
            enableAdminConsentRequests   = & $AsFlag $V.EnableAdminConsentRequests
        }
        Current  = $Current
    }
}

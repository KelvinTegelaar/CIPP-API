function Get-CIPPBaselineDisableInactiveAppsState {
    <#
    .SYNOPSIS
        Prepare hook for DisableInactiveApps: enabled enterprise apps with no sign-in within the
        configured window.
    .DESCRIPTION
        Joins the ServicePrincipals cache with the ServicePrincipalSignInActivities cache (the Entra
        sign-in activity report, Entra ID P1). The report only lists apps that have signed in, so an
        app without a row has never signed in and counts as inactive once it is older than the window.

        The window is measured from when the report was collected rather than from now: if that
        collection starts failing, its old rows must not make an app in daily use look idle.

        Microsoft-owned apps (Config/VendorTenantList.json) and CIPP's own app are never offenders,
        and neither is an app an admin re-enabled in the last 7 days. Exclusions are resolved through
        Get-CIPPTextReplacement as one JSON array, so a List variable expands into its entries and an
        empty one ([]) drops out. A variable left unresolved stops the run instead of disabling the
        app it was meant to protect.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $CheckDays = if ([string]::IsNullOrWhiteSpace("$($Item.Variables.days)")) { 180 } else { [int]$Item.Variables.days }
    if ($CheckDays -lt 30) { throw "DisableInactiveApps: a threshold of $CheckDays days is below the 30-day floor - refusing to run to prevent mass app changes." }

    $Excluded = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Entries = @(foreach ($Entry in @($Item.Variables.excludedApps)) { $Value = "$($Entry.value ?? $Entry)".Trim(); if ($Value) { $Value } })
    if ($Entries.Count -gt 0) {
        $Resolved = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text (ConvertTo-Json -Compress -InputObject $Entries) -EscapeForJson
        foreach ($Entry in @(ConvertFrom-Json -InputObject $Resolved)) {
            $Value = "$Entry".Trim()
            if ($Value -match '^%[^%\s]+%$') { throw [System.ArgumentException]::new("DisableInactiveApps: excluded app $Value is not defined for $TenantFilter. Add it under Custom Variables, globally or for this tenant.") }
            if ($Value) { [void]$Excluded.Add($Value) }
        }
    }

    $ServicePrincipals = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ServicePrincipals' | Where-Object { $_ })
    if ($ServicePrincipals.Count -eq 0) { return @{ Current = $null } }

    $Activities = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ServicePrincipalSignInActivities')
    $Collected = @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'ServicePrincipalSignInActivities' -CountsOnly)[0]
    if (-not $Collected.Timestamp) { return @{ Current = $null } }
    $Cutoff = ([datetimeoffset]$Collected.Timestamp).UtcDateTime.AddDays(-$CheckDays)

    $LastSignIn = [System.Collections.Generic.Dictionary[string, datetime]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Activity in $Activities) {
        $Raw = $Activity.lastSignInActivity.lastSignInDateTime
        if ($Activity.appId -and $Raw) { $LastSignIn["$($Activity.appId)"] = ([datetimeoffset]$Raw).UtcDateTime }
    }

    $VendorTenants = Get-CIPPVendorTenantMap
    $CippAppId = [Environment]::GetEnvironmentVariable('ApplicationID')
    $Inactive = [System.Collections.Generic.List[object]]::new()
    foreach ($Sp in $ServicePrincipals) {
        if ($Sp.accountEnabled -ne $true -or $Sp.servicePrincipalType -ne 'Application') { continue }
        if ($CippAppId -and $Sp.appId -eq $CippAppId) { continue }
        $Vendor = $null
        if ($Sp.appOwnerOrganizationId -and $VendorTenants.TryGetValue("$($Sp.appOwnerOrganizationId)", [ref]$Vendor) -and $Vendor.VendorType -eq 'Microsoft') { continue }
        if ($Excluded.Contains("$($Sp.displayName)") -or $Excluded.Contains("$($Sp.appId)") -or $Excluded.Contains("$($Sp.id)")) { continue }
        if (-not $Sp.createdDateTime -or ([datetimeoffset]$Sp.createdDateTime).UtcDateTime -gt $Cutoff) { continue }
        $Last = [datetime]::MinValue
        if ($LastSignIn.TryGetValue("$($Sp.appId)", [ref]$Last) -and $Last -gt $Cutoff) { continue }
        $Inactive.Add($Sp)
    }

    if ($Inactive.Count -gt 0) {
        $Reenabled = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $AuditLookup = (Get-Date).AddDays(-7).ToUniversalTime().ToString('o')
        try {
            $Audits = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/auditLogs/directoryAudits?`$filter=activityDisplayName eq 'Update service principal' and activityDateTime ge $AuditLookup&`$select=targetResources" -tenantid $TenantFilter
            foreach ($Target in @($Audits.targetResources)) {
                if (@($Target.modifiedProperties).Where({ $_.displayName -eq 'AccountEnabled' -and "$($_.newValue)" -match 'true' }).Count -gt 0) { [void]$Reenabled.Add("$($Target.id)") }
            }
        } catch {
            Write-Information "Baselines: re-enable audit lookup on $TenantFilter failed: $($_.Exception.Message)"
        }
        $Inactive = @($Inactive.Where({ -not $Reenabled.Contains("$($_.id)") }))
    }

    @{
        Current = [PSCustomObject]@{
            offenders = @(@(foreach ($Sp in $Inactive) { '{0} ({1})' -f $Sp.displayName, $Sp.appId }) | Sort-Object)
            targets   = @(foreach ($Sp in $Inactive) { [PSCustomObject]@{ id = "$($Sp.id)" } })
        }
    }
}

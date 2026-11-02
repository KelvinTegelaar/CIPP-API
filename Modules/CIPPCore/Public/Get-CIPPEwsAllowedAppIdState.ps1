function Get-CIPPEwsAllowedAppIdState {
    <#
    .SYNOPSIS
        Reads a tenant's EWS app-ID allow list and works out the additive target list.
    .DESCRIPTION
        Shared by the EWSAllowedAppIds standard and its baseline hook. Set-OrganizationConfig
        replaces the whole EwsAllowedAppIDs list on every write, so the target is always the
        current list plus the required IDs. Known-malicious app IDs are never added, and are
        only removed from the list when -RemoveMaliciousApps is set.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$TenantFilter,
        $Presets,
        $CustomAppIds,
        [bool]$IncludeEwsPermissionApps = $false,
        [bool]$IncludeHybridApp = $true,
        [bool]$RemoveMaliciousApps = $false,
        $LogApi = 'Standards'
    )

    # Preset key -> app IDs. The frontend option values are these keys.
    $PresetMap = @{
        MicrosoftOffice    = @('d3590ed6-52b3-4102-aeff-aad2292ab01c')
        PowerQuery         = @('a672d62c-fc7b-4e81-a576-e60dc46e951d')
        PowerBIDataRefresh = @('b52893c8-bc2e-47fc-918b-77022b299bbc')
        AppleMail          = @('f8d98a96-0999-43f5-8af3-69971c7bb423')
        AvePointCloud      = @('8347dcbb-c18a-4a06-ad9d-c4ade6daba43', 'c21d796d-56a5-4305-a7df-047371fa9fd7', 'b14c93d6-47fe-4ace-afcd-006fc1fbfabb', '34be87c0-bd08-47ab-8ecf-38f6340592f3', '83043760-a2ba-4185-8611-0e6d94a0905b', 'ec377498-817e-4ec8-89be-f3917a7a8bdd')
        AvePointFlyServer  = @('1051e7ac-3119-477f-9c35-420b22bfbf13', '6d5ebe16-e826-4621-b839-d14134299a73', '44d3d6d8-eee8-416e-8c86-09cdabc778e9', 'abab2369-6eb4-4c00-bd60-9438dc9d6514')
    }
    $DefaultPresets = @('MicrosoftOffice', 'PowerQuery', 'PowerBIDataRefresh', 'AppleMail')

    # Picker values arrive as {label, value} wrappers or plain strings.
    $Unwrap = { param($Value) @($Value | ForEach-Object { $_.value ?? $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace("$_") } | ForEach-Object { "$_".Trim() }) }

    $Config = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-OrganizationConfig' -cmdParams @{ RetrieveEwsOperationAccessPolicy = $true }
    # The list can come back as one comma-separated string or as an array.
    $CurrentAppIds = [System.Collections.Generic.List[string]]::new()
    $CurrentSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Id in (@($Config.EwsAllowedAppIDs) -join ',') -split '[,;\s]+') {
        if ([string]::IsNullOrWhiteSpace($Id)) { continue }
        $Normalized = $Id.Trim().ToLowerInvariant()
        if ($CurrentSet.Add($Normalized)) { $CurrentAppIds.Add($Normalized) }
    }

    $Candidates = [System.Collections.Generic.List[object]]::new()

    $PresetKeys = & $Unwrap $Presets
    if ($PresetKeys.Count -eq 0) { $PresetKeys = $DefaultPresets }
    foreach ($Key in $PresetKeys) {
        if (-not $PresetMap.ContainsKey($Key)) {
            Write-LogMessage -API $LogApi -tenant $TenantFilter -message "EWS allowed apps: unknown preset '$Key' skipped." -sev Warning
            continue
        }
        foreach ($Id in $PresetMap[$Key]) { $Candidates.Add(@{ Id = $Id; Source = "preset $Key" }) }
    }

    # Custom entries may hold tenant variables that expand to one or more IDs.
    foreach ($Entry in (& $Unwrap $CustomAppIds)) {
        $Expanded = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text $Entry
        foreach ($Part in ("$Expanded" -split '[,;\s]+' | Where-Object { $_ })) {
            $Guid = [guid]::Empty
            if ([guid]::TryParse($Part, [ref]$Guid)) {
                $Candidates.Add(@{ Id = $Guid.ToString(); Source = 'custom' })
            } else {
                Write-LogMessage -API $LogApi -tenant $TenantFilter -message "EWS allowed apps: custom entry '$Part' (from '$Entry') is not a valid app ID and was skipped." -sev Warning
            }
        }
    }

    if ($IncludeEwsPermissionApps -or $IncludeHybridApp) {
        try {
            $PermissionApps = @(Get-CIPPEwsPermissionApps -TenantFilter $TenantFilter | Where-Object { $_.appId })
            if ($IncludeEwsPermissionApps) {
                foreach ($App in $PermissionApps) { $Candidates.Add(@{ Id = $App.appId; Source = "EWS permission holder '$($App.displayName)'" }) }
            }
            if ($IncludeHybridApp) {
                $HybridApps = @($PermissionApps | Where-Object { $_.isExchangeHybridApp })
                foreach ($App in $HybridApps) { $Candidates.Add(@{ Id = $App.appId; Source = "Exchange hybrid app '$($App.displayName)'" }) }
            }
        } catch {
            # Discovery only adds IDs; a failure must not block the rest of the list.
            Write-LogMessage -API $LogApi -tenant $TenantFilter -message "EWS allowed apps: could not discover apps holding EWS permissions: $($_.Exception.Message)" -sev Warning
        }
    }

    $Malicious = (Get-CIPPBecRogueAppFeed).Apps
    $IsMalicious = { param($Id) $Malicious -and $Malicious.ContainsKey($Id.ToLowerInvariant()) }

    $RequiredAppIds = [System.Collections.Generic.List[string]]::new()
    $RequiredSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Candidate in $Candidates) {
        $Id = $Candidate.Id.ToLowerInvariant()
        if (& $IsMalicious $Id) {
            Write-LogMessage -API $LogApi -tenant $TenantFilter -message "EWS allowed apps: $Id ($($Malicious[$Id].Name)) from $($Candidate.Source) is a known-malicious app and was not added." -sev Warning
            continue
        }
        if ($RequiredSet.Add($Id)) { $RequiredAppIds.Add($Id) }
    }

    $MissingAppIds = @($RequiredAppIds | Where-Object { -not $CurrentSet.Contains($_) })
    $MaliciousPresent = @($CurrentAppIds | Where-Object { & $IsMalicious $_ })
    foreach ($Id in $MaliciousPresent) {
        Write-LogMessage -API $LogApi -tenant $TenantFilter -message "EWS allowed apps: known-malicious app $Id ($($Malicious[$Id].Name)) is on the tenant's EWS allow list." -sev Alert
    }

    $DesiredAppIds = [System.Collections.Generic.List[string]]::new()
    foreach ($Id in $CurrentAppIds) {
        if ($RemoveMaliciousApps -and $MaliciousPresent -contains $Id) { continue }
        $DesiredAppIds.Add($Id)
    }
    foreach ($Id in $MissingAppIds) { $DesiredAppIds.Add($Id) }

    $NeedsWrite = $Config.EwsEnabled -ne $true -or $MissingAppIds.Count -gt 0 -or ($RemoveMaliciousApps -and $MaliciousPresent.Count -gt 0)
    if ($NeedsWrite -and $DesiredAppIds.Count -eq 0) {
        # EwsEnabled with an empty list blocks all EWS, so never write one.
        Write-LogMessage -API $LogApi -tenant $TenantFilter -message 'EWS allowed apps: the resulting allow list would be empty, so nothing was changed.' -sev Warning
        $NeedsWrite = $false
    }

    [PSCustomObject]@{
        EwsEnabled             = $Config.EwsEnabled
        CurrentAppIds          = @($CurrentAppIds)
        RequiredAppIds         = @($RequiredAppIds)
        MissingAppIds          = @($MissingAppIds)
        MaliciousAppIdsPresent = @($MaliciousPresent)
        DesiredAppIds          = @($DesiredAppIds)
        NeedsWrite             = [bool]$NeedsWrite
    }
}

function Get-CIPPBaselinePhishSimSpoofIntelligenceState {
    <#
    .SYNOPSIS
        Prepare hook for PhishSimSpoofIntelligence: spoof intelligence allowances for
        phishing simulation senders.
    .DESCRIPTION
        Additive by default: grades which configured sending infrastructures are missing
        from the spoof allow list, leaving operator-added entries alone. The
        RemoveExtraDomains switch turns on the strict mode the classic offered, where
        entries outside the configured set grade (and remediate) as removals - the operator
        opts into ownership of the whole list.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $SpoofItems = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoTenantAllowBlockListSpoofItems')
    if ($SpoofItems.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'ExoTenantAllowBlockListSpoofItems')) {
        return @{ Current = $null }
    }

    $Allowed = @(@($Item.Variables.AllowedDomains) | ForEach-Object { "$($_.value ?? $_)" } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($Allowed.Count -eq 0) { return @{ Current = $null } }
    $RemoveExtra = [bool]($Item.Variables.RemoveExtraDomains -eq $true)

    $ExistingInfra = @($SpoofItems | ForEach-Object { "$($_.SendingInfrastructure)" })
    $Missing = @($Allowed | Where-Object { $ExistingInfra -notcontains $_ } | Sort-Object)

    $Expected = [PSCustomObject]@{ missingDomains = @() }
    $Current = [PSCustomObject]@{ missingDomains = @($Missing) }
    $ExtraItems = @()
    if ($RemoveExtra) {
        $ExtraItems = @($SpoofItems | Where-Object { $Allowed -notcontains "$($_.SendingInfrastructure)" })
        $Expected | Add-Member -NotePropertyName 'extraDomains' -NotePropertyValue @()
        $Current | Add-Member -NotePropertyName 'extraDomains' -NotePropertyValue @($ExtraItems | ForEach-Object { "$($_.SendingInfrastructure)" } | Sort-Object)
    }
    # Carried for the executor: removals key on the item Identity, not the domain.
    $Current | Add-Member -NotePropertyName 'extraItemIds' -NotePropertyValue @($ExtraItems | ForEach-Object { "$($_.Identity)" })

    @{ Expected = $Expected; Current = $Current }
}

function Get-CIPPBaselinePhishingSimulationsState {
    <#
    .SYNOPSIS
        Prepare hook for PhishingSimulations: the phish sim override policy, its rule, and
        the advanced-delivery URL allowances.
    .DESCRIPTION
        Three legs, graded separately so the drift row names the broken one: the override
        POLICY must exist enabled, the override RULE must carry the configured sender IP
        ranges and domains, and the configured simulation URLs must be on the Url
        advanced-delivery allow list.

        Rule lists and URLs are additive by default; RemoveExtraUrls opts into strict
        ownership where entries outside the configured set grade as removals - the classic's
        exact switch, applied to all three lists.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Item,
        $TenantFilter
    )

    $Policies = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoPhishSimOverridePolicy' -CollectorType 'ExoPhishSimConfig')
    $Rules = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoPhishSimOverrideRule' -CollectorType 'ExoPhishSimConfig')
    $UrlItems = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'ExoPhishSimUrlAllowItems' -CollectorType 'ExoPhishSimConfig')
    if ($Policies.Count -eq 0 -and $Rules.Count -eq 0 -and -not (Test-CIPPBaselineCacheCollected -TenantFilter $TenantFilter -Type 'ExoPhishSimOverridePolicy')) {
        return @{ Current = $null }
    }

    $Unwrap = { param($Value) @(@($Value) | ForEach-Object { "$($_.value ?? $_)" } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) }
    $WantedDomains = & $Unwrap $Item.Variables.Domains
    $WantedRanges = & $Unwrap $Item.Variables.SenderIpRanges
    $WantedUrls = & $Unwrap $Item.Variables.PhishingSimUrls
    if ($WantedDomains.Count -eq 0 -or $WantedRanges.Count -eq 0) { return @{ Current = $null } }
    $RemoveExtra = [bool]($Item.Variables.RemoveExtraUrls -eq $true)

    $Policy = $Policies | Where-Object { "$($_.Name)" -eq 'PhishSimOverridePolicy' } | Select-Object -First 1
    $Rule = $Rules | Where-Object { "$($_.Name)" -like '*PhishSimOverr*' } | Select-Object -First 1

    $CurrentRanges = @($Rule.SenderIpRanges | ForEach-Object { "$_" })
    $CurrentDomains = @($Rule.Domains | ForEach-Object { "$_" })
    $CurrentUrls = @($UrlItems | ForEach-Object { "$($_.Value)" })

    $MissingRanges = @($WantedRanges | Where-Object { $CurrentRanges -notcontains $_ } | Sort-Object)
    $MissingDomains = @($WantedDomains | Where-Object { $CurrentDomains -notcontains $_ } | Sort-Object)
    $MissingUrls = @($WantedUrls | Where-Object { $CurrentUrls -notcontains $_ } | Sort-Object)
    $ExtraRanges = @(); $ExtraDomains = @(); $ExtraUrls = @()
    if ($RemoveExtra) {
        $ExtraRanges = @($CurrentRanges | Where-Object { $WantedRanges -notcontains $_ } | Sort-Object)
        $ExtraDomains = @($CurrentDomains | Where-Object { $WantedDomains -notcontains $_ } | Sort-Object)
        $ExtraUrls = @($CurrentUrls | Where-Object { $WantedUrls -notcontains $_ } | Sort-Object)
    }

    $Expected = [PSCustomObject]@{
        policyEnabled  = $true
        missingDomains = @(); missingSenderIpRanges = @(); missingUrls = @()
    }
    $Current = [PSCustomObject]@{
        policyEnabled  = [bool]($Policy -and $Policy.Enabled -eq $true)
        missingDomains = @($MissingDomains); missingSenderIpRanges = @($MissingRanges); missingUrls = @($MissingUrls)
    }
    if ($RemoveExtra) {
        $Expected | Add-Member -NotePropertyName 'extraDomains' -NotePropertyValue @()
        $Expected | Add-Member -NotePropertyName 'extraSenderIpRanges' -NotePropertyValue @()
        $Expected | Add-Member -NotePropertyName 'extraUrls' -NotePropertyValue @()
        $Current | Add-Member -NotePropertyName 'extraDomains' -NotePropertyValue @($ExtraDomains)
        $Current | Add-Member -NotePropertyName 'extraSenderIpRanges' -NotePropertyValue @($ExtraRanges)
        $Current | Add-Member -NotePropertyName 'extraUrls' -NotePropertyValue @($ExtraUrls)
    }
    # Carried for the executor.
    $Current | Add-Member -NotePropertyName 'policyExists' -NotePropertyValue ([bool]$Policy)
    $Current | Add-Member -NotePropertyName 'ruleExists' -NotePropertyValue ([bool]$Rule)
    $Current | Add-Member -NotePropertyName 'ruleIdentity' -NotePropertyValue "$($Rule.Identity)"

    @{ Expected = $Expected; Current = $Current }
}

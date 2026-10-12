function Invoke-CIPPBaselinePhishingSimulations {
    <#
    .SYNOPSIS
        PhishingSimulations executor: aligns the phish sim override policy, rule and URL
        allowances.
    .DESCRIPTION
        Three legs, each only when its part drifted, all the classic's writes: the override
        policy is enabled in place or created; the rule takes Add/Remove deltas when it
        exists (Set-ExoPhishSimOverrideRule speaks in deltas, not replacement lists) and is
        created with the full configured lists otherwise; simulation URLs add to and - in
        strict mode - remove from the Url advanced-delivery allow list.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Unwrap = { param($Value) @(@($Value) | ForEach-Object { "$($_.value ?? $_)" } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) }
    $WantedDomains = & $Unwrap $Remediate.domains
    $WantedRanges = & $Unwrap $Remediate.senderIpRanges

    if ($Current.policyEnabled -ne $true) {
        if ($Current.policyExists -eq $true) {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-PhishSimOverridePolicy' -cmdParams @{ Identity = 'CIPPPhishSim'; Enabled = $true }
        } else {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-PhishSimOverridePolicy' -cmdParams @{ Name = 'CIPPPhishSim'; Enabled = $true }
        }
    }

    $RuleNeedsWork = @($Current.missingDomains).Count -gt 0 -or @($Current.missingSenderIpRanges).Count -gt 0 -or
    @($Current.extraDomains).Count -gt 0 -or @($Current.extraSenderIpRanges).Count -gt 0
    if ($RuleNeedsWork) {
        if ($Current.ruleExists -eq $true) {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-ExoPhishSimOverrideRule' -cmdParams @{
                Identity             = "$($Current.ruleIdentity)"
                AddSenderIpRanges    = @($Current.missingSenderIpRanges)
                AddDomains           = @($Current.missingDomains)
                RemoveSenderIpRanges = @($Current.extraSenderIpRanges)
                RemoveDomains        = @($Current.extraDomains)
            }
        } else {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-ExoPhishSimOverrideRule' -cmdParams @{
                Name = 'CIPPPhishSim'; Policy = 'PhishSimOverridePolicy'; SenderIpRanges = @($WantedRanges); Domains = @($WantedDomains)
            }
        }
    }

    if (@($Current.extraUrls).Count -gt 0) {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Remove-TenantAllowBlockListItems' -cmdParams @{
            ListType = 'Url'; ListSubType = 'AdvancedDelivery'; Entries = @($Current.extraUrls)
        }
    }
    if (@($Current.missingUrls).Count -gt 0) {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-TenantAllowBlockListItems' -cmdParams @{
            ListType = 'Url'; ListSubType = 'AdvancedDelivery'; Allow = $true; Entries = @($Current.missingUrls)
        }
    }
    Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Aligned the phishing simulation overrides.' -Sev 'Info'
}

function Invoke-CIPPBaselineTransportRuleTemplate {
    <#
    .SYNOPSIS
        TransportRuleTemplate executor: deploys the template's transport rule.
    .DESCRIPTION
        New- when the rule is absent, Set- when it exists AND the baseline opted into
        overwriting. That opt-in is the classic behaviour and matters: a transport rule is
        frequently tuned by hand after deployment, so overwriting without being asked would
        silently discard those edits. Without it an existing rule is left exactly as it is.

        The property exclusion list is carried verbatim from the classic standard - those
        fields are returned by Get-TransportRule but rejected by New-/Set-TransportRule, so
        passing them through fails the whole write.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Bodies = @($Current.ruleBodies | Where-Object { $_ })
    if ($Bodies.Count -eq 0) { return }

    $Deployed = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Name in @($Current.deployedNames)) { if ($Name) { [void]$Deployed.Add("$Name") } }

    $Excluded = @('GUID', 'Comments', 'HasSenderOverride', 'ExceptIfHasSenderOverride',
        'ExceptIfMessageContainsDataClassifications', 'MessageContainsDataClassifications', 'UseLegacyRegex')

    foreach ($Body in $Bodies) {
        $RuleName = "$($Body.name)"
        $Parameters = @{}
        foreach ($Property in $Body.PSObject.Properties) {
            if ($Excluded -contains $Property.Name) { continue }
            $Parameters[$Property.Name] = $Property.Value
        }

        if ($Deployed.Contains($RuleName)) {
            if ($Remediate.overwrite -ne $true) {
                Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Transport rule '$RuleName' already exists and overwrite is off - leaving it untouched." -Sev 'Info'
                continue
            }
            $Parameters['Identity'] = $RuleName
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-TransportRule' -cmdParams $Parameters -useSystemMailbox $true
        } else {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-TransportRule' -cmdParams $Parameters -useSystemMailbox $true
            [void]$Deployed.Add($RuleName)
        }
    }
}

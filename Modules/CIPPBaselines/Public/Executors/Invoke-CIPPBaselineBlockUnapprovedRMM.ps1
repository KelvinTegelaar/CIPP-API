function Invoke-CIPPBaselineBlockUnapprovedRMM {
    <#
    .SYNOPSIS
        BlockUnapprovedRMM executor: creates or updates the Windows and macOS policies that block
        RMM and remote access tools.
    .DESCRIPTION
        Builds each policy from the bundled tool list and deploys it through Set-CIPPIntunePolicy,
        which updates the policy of the same name when it exists. A platform that is switched off, or
        has no rule left after the allowed tools are taken out, is skipped; its policy is not removed.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $AllowedTools = @($Remediate.allowedTools | ForEach-Object { "$($_.value ?? $_)".Trim() } | Where-Object { $_ })
    $AssignTo = if ("$($Remediate.customGroup)") { "$($Remediate.customGroup)" } else { "$($Remediate.assignTo.value ?? $Remediate.assignTo)" }
    $ExcludeGroup = "$($Remediate.excludeGroup)"

    foreach ($Platform in @('Windows', 'macOS')) {
        if ("$($Remediate.$Platform)" -eq 'False') { continue }
        $Policy = Get-CIPPBaselineRmmBlockPolicy -Platform $Platform -AllowedTools $AllowedTools -AssignmentKey "$AssignTo|$ExcludeGroup"
        if (-not $Policy) { continue }

        $PolicyParams = @{
            TemplateType = 'Catalog'
            DisplayName  = $Policy.Name
            RawJSON      = $Policy.RawJSON
            TenantFilter = $TenantFilter
            APIName      = 'Baselines'
        }
        if ($AssignTo -and $AssignTo -notin @('On', 'none')) {
            $PolicyParams.AssignTo = $AssignTo
            $PolicyParams.ExcludeGroup = $ExcludeGroup
        }
        $null = Set-CIPPIntunePolicy @PolicyParams
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Deployed '$($Policy.Name)' with $($Policy.RuleCount) rules from tool list $($Policy.ListVersion)." -Sev 'Info'
    }
}

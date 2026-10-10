function Test-CIPPCAGapMicrosoftManagedPolicy {
    <#
    .SYNOPSIS
        Surfaces Microsoft-managed Conditional Access policies detected by their display names.
    .DESCRIPTION
        Per policy: a disabled policy whose name matches a Microsoft-managed policy pattern gets an Info
        finding pointing at the MC1246002 Baseline Security Mode phantom-draft issue.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $Findings = [System.Collections.Generic.List[object]]::new()
    $Keywords = @($Context.Data.Reference.managedPolicyPatterns | ForEach-Object { "$($_.keyword)".ToLowerInvariant() })

    $IsManaged = {
        param($P)
        $Name = "$($P.displayName)".ToLowerInvariant()
        foreach ($Keyword in $Keywords) { if ($Name.Contains($Keyword)) { return $true } }
        $false
    }

    foreach ($Policy in @($Context.Policies)) {
        if (-not (& $IsManaged $Policy) -or $Policy.state -ne 'disabled') { continue }
        $Params = @{
            Severity         = 'Info'
            Category         = 'Microsoft-managed policies'
            Title            = 'Microsoft-managed policy is switched off'
            Description      = 'Microsoft has created disabled draft copies of its managed policies in some tenants without being asked, and removes those drafts itself. If nobody in your organization switched this policy off, that is the likely explanation and there is no exposure from it.'
            Remediation      = 'No change needed if Microsoft created this draft. If the policy was switched off deliberately, consider running it in report-only mode to see what it would do.'
            AffectedPolicies = @($Policy.displayName)
            DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/managed-policies'
        }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    }

    $ManagedPolicies = @($Context.Policies | Where-Object { & $IsManaged $_ })
    if ($ManagedPolicies.Count -gt 0) {
        $ReportOnlyCount = @($ManagedPolicies | Where-Object { $_.state -eq 'enabledForReportingButNotEnforced' }).Count
        $DisabledCount = @($ManagedPolicies | Where-Object { $_.state -eq 'disabled' }).Count
        $Names = @($ManagedPolicies | ForEach-Object { $_.displayName })
        $Detail = "The managed policies are $($Names -join ', '). "
        if ($ReportOnlyCount -gt 0) { $Detail += "$ReportOnlyCount of them are in report-only mode. " }
        if ($DisabledCount -gt 0) { $Detail += "$DisabledCount of them are disabled. " }
        $Detail += 'Microsoft maintains these policies and adjusts them as the tenant changes; they cannot be renamed or deleted and may overlap with your own policies. '

        $Params = @{
            Severity         = 'Info'
            Category         = 'Microsoft-managed policies'
            Title            = "$($ManagedPolicies.Count) Microsoft-managed policy(ies) are present in the tenant"
            Description      = $Detail
            Remediation      = 'Check the managed policies against your own for overlap, and consider enforcing the ones still in report-only mode.'
            AffectedPolicies = $Names
            DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/managed-policies'
        }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    }

    @($Findings)
}

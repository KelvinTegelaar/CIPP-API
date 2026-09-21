function Test-CIPPCAGapResourceExclusionBypass {
    <#
    .SYNOPSIS
        Tenant-wide check for "All resources" policies with app exclusions affected by Low-Privilege Scope
        Enforcement.
    .DESCRIPTION
        Until 2026, excluding any app from an All-resources policy silently exempted low-privilege scopes
        (User.Read, openid, profile, email, offline_access, People.Read) from enforcement.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $Findings = [System.Collections.Generic.List[object]]::new()
    $AzureAdGraph = "$($Context.Data.Reference.windowsAzureAdResource)"

    $PoliciesWithExclusions = @($Context.Enabled | Where-Object {
            $Apps = $_.conditions.applications
            (@($Apps.includeApplications) -contains 'All') -and (@($Apps.excludeApplications).Count -gt 0)
        })
    if ($PoliciesWithExclusions.Count -eq 0) { return @($Findings) }

    $Names = @($PoliciesWithExclusions | ForEach-Object { $_.displayName })
    $TotalExclusions = 0
    foreach ($Policy in $PoliciesWithExclusions) { $TotalExclusions += @($Policy.conditions.applications.excludeApplications).Count }
    $HasAzureAdGraphPolicy = @($Context.Enabled | Where-Object { @($_.conditions.applications.includeApplications | Where-Object { "$_".ToLowerInvariant() -eq $AzureAdGraph }).Count -gt 0 }).Count -gt 0

    $CoverageNote = if ($HasAzureAdGraphPolicy) {
        ' A policy already covers the directory service through which these basic permissions are now enforced, so the change is accounted for.'
    } else {
        ' No policy covers the directory service through which these basic permissions are now enforced, so applications that only ask for basic profile details may be challenged unexpectedly or, depending on rollout, still slip through.'
    }

    $Params = @{
        Severity         = if ($HasAzureAdGraphPolicy) { 'Info' } else { 'Medium' }
        Category         = 'Exemption scope'
        Title            = "$($PoliciesWithExclusions.Count) tenant-wide policy(ies) with exemptions are affected by a Microsoft change"
        Description      = "The enforced policies $($Names -join ', ') cover every application but exempt $TotalExclusions application(s) between them. Until recently, any such exemption also let applications read basic profile and directory details without meeting the policy. Microsoft now enforces those basic permissions through the directory service itself, which closes that path but may change how applications that relied on it behave.$CoverageNote"
        Remediation      = 'Aim for tenant-wide policies without application exemptions, giving applications that need lighter requirements a policy of their own, and cover the directory service explicitly where exemptions must remain.'
        AffectedPolicies = $Names
        RelatedIds       = @($AzureAdGraph)
        DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/concept-conditional-access-cloud-apps#new-conditional-access-behavior-when-an-all-resources-policy-has-a-resource-exclusion'
    }
    if (-not $HasAzureAdGraphPolicy) { $Params['CaTemplate'] = "$($Context.Data.Reference.templates.windowsAzureAdBaselineScopes)" }
    $Findings.Add((New-CIPPCAGapFinding @Params))

    @($Findings)
}

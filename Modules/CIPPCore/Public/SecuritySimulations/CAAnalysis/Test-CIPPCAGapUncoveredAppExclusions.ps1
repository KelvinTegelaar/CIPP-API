function Test-CIPPCAGapUncoveredAppExclusions {
    <#
    .SYNOPSIS
        Tenant-wide check for apps excluded from "All resources" policies that no other policy covers.
    .DESCRIPTION
        Collects every app excluded from an enabled All-resources policy and checks whether any other
        enabled policy targets it directly or via All resources without excluding it.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $Findings = [System.Collections.Generic.List[object]]::new()

    $ExcludedFromAllResources = [ordered]@{}
    foreach ($Policy in @($Context.Enabled)) {
        $Apps = $Policy.conditions.applications
        if (-not (@($Apps.includeApplications) -contains 'All')) { continue }
        foreach ($AppId in @($Apps.excludeApplications)) {
            $Key = "$AppId"
            if (-not $ExcludedFromAllResources.Contains($Key)) { $ExcludedFromAllResources[$Key] = [System.Collections.Generic.List[string]]::new() }
            $ExcludedFromAllResources[$Key].Add($Policy.displayName)
        }
    }

    $Uncovered = [System.Collections.Generic.List[object]]::new()
    foreach ($AppId in @($ExcludedFromAllResources.Keys)) {
        $IsCovered = @($Context.Enabled | Where-Object {
                $Apps = $_.conditions.applications
                if (@($Apps.excludeApplications) -contains $AppId) { return $false }
                if (@($Apps.includeApplications) -contains $AppId) { return $true }
                if (@($Apps.includeApplications) -contains 'All') { return $true }
                $false
            }).Count -gt 0
        if ($IsCovered) { continue }
        $Uncovered.Add([PSCustomObject]@{
                appId        = $AppId
                displayName  = Get-CIPPCAAppDisplayName -AppId $AppId -Context $Context
                excludedFrom = [string[]]@($ExcludedFromAllResources[$AppId])
            })
    }

    if ($Uncovered.Count -gt 0) {
        $AppList = @($Uncovered | ForEach-Object { "- $($_.displayName), exempt from $($_.excludedFrom -join ', ')" }) -join "`n"
        $Affected = [System.Collections.Generic.List[string]]::new()
        foreach ($Entry in $Uncovered) { foreach ($Name in $Entry.excludedFrom) { if (-not $Affected.Contains($Name)) { $Affected.Add($Name) } } }
        $Params = @{
            Severity         = 'High'
            Category         = 'Application coverage'
            Title            = "$($Uncovered.Count) application(s) are subject to no Conditional Access policy at all"
            Description      = "These applications are exempt from the tenant-wide policies and no other policy covers them, so sign-ins to them face no requirements:`n$AppList`n`nSome applications cannot be selected individually in a policy, in which case a tenant-wide policy is the only way to protect them."
            Remediation      = 'Remove each exemption from the tenant-wide policy and, where an application genuinely needs different requirements, give it a policy of its own.'
            AffectedPolicies = @($Affected)
            RelatedIds       = @($Uncovered | ForEach-Object { $_.appId })
            DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/concept-conditional-access-cloud-apps'
        }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    }

    @($Findings)
}

function Test-CIPPCAGapKnownBypassApps {
    <#
    .SYNOPSIS
        Reviews every non-FOCI app excluded from a policy and cross-references it with the known bypass-app
        catalog.
    .DESCRIPTION
        One consolidated "App Exclusion" finding per policy that excludes apps (FOCI apps are covered by
        Test-CIPPCAGapFociExclusion).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $Findings = [System.Collections.Generic.List[object]]::new()
    $Data = $Context.Data

    foreach ($Policy in @($Context.Policies)) {
        $Details = [System.Collections.Generic.List[object]]::new()
        $HasHighRisk = $false

        foreach ($AppId in @($Policy.conditions.applications.excludeApplications)) {
            $Key = "$AppId".ToLowerInvariant()
            if ($null -ne $Data.FociById[$Key]) { continue }

            $ServicePrincipal = $Context.ServicePrincipals[$Key]
            $BypassApp = $Data.BypassAppById[$Key]
            $Description = $Data.AppDescriptionById[$Key]
            $Alias = $Data.AppGroupAliases[$Key]

            $Name = $Description.displayName ?? $ServicePrincipal.displayName ?? $BypassApp.displayName ?? $Alias.displayName ?? "$AppId"
            $ServicePrincipalPurpose = if ($ServicePrincipal) { "An application registered in this tenant (type: $($ServicePrincipal.servicePrincipalType ?? 'Application'))." } else { 'An application that is neither registered in this tenant nor listed in the known catalog.' }
            $Purpose = $Description.purpose ?? $BypassApp.description ?? $Alias.purpose ?? $ServicePrincipalPurpose
            $Reason = $Description.commonExclusionReason ?? 'No common reason for exempting this application is known.'
            $Risk = $Description.exclusionRisk ?? $(if ($BypassApp) { 'high' } else { 'medium' })

            if ($Risk -in @('critical', 'high') -or $null -ne $BypassApp) { $HasHighRisk = $true }

            $Details.Add([PSCustomObject]@{
                    appId           = "$AppId"
                    displayName     = "$Name"
                    purpose         = "$Purpose"
                    exclusionReason = "$Reason"
                    risk            = "$Risk"
                })
        }

        if ($Details.Count -eq 0) { continue }

        $HighRiskApps = @($Details | Where-Object { $_.risk -in @('critical', 'high') })
        $AppNames = @($Details | ForEach-Object { $_.displayName }) -join ', '
        $RiskSummary = if ($HighRiskApps.Count -gt 0) {
            "The higher-risk exemptions are $(@($HighRiskApps | ForEach-Object { $_.displayName }) -join ', ')."
        } else {
            'None of these exemptions is considered high risk.'
        }
        $PerApp = @($Details | ForEach-Object { "- $($_.displayName) ($($_.risk) risk): $($_.purpose) $($_.exclusionReason)" }) -join "`n"
        $HighRiskSuffix = if ($HighRiskApps.Count -gt 0) { ", $($HighRiskApps.Count) of them high risk" } else { '' }

        $Params = @{
            Severity         = if ($HasHighRisk) { 'High' } else { 'Medium' }
            Category         = 'Application exemptions'
            Title            = "$($Details.Count) application(s) exempt from this policy$HighRiskSuffix"
            Description      = "Sign-ins through $AppNames are not subject to the requirements of this policy. $RiskSummary`n`n$PerApp"
            Remediation      = 'Keep only the exemptions with a documented business reason, and give applications that need lighter requirements a policy of their own instead.'
            AffectedPolicies = @($Policy.displayName)
            RelatedIds       = @($Details | ForEach-Object { $_.appId })
            DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/concept-conditional-access-cloud-apps'
        }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    }

    @($Findings)
}

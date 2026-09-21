function Test-CIPPCAGapHighValueApps {
    <#
    .SYNOPSIS
        Tenant-wide check that high-value Microsoft applications are covered by an MFA or block policy.
    .DESCRIPTION
        For Azure Management, Azure Portal, Microsoft Graph, Exchange Online and SharePoint Online: covered
        when an enabled policy includes the app (directly or via All apps) without excluding it and requires
        MFA, an authentication strength, or blocks.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $Findings = [System.Collections.Generic.List[object]]::new()
    $Unprotected = [System.Collections.Generic.List[object]]::new()

    foreach ($App in @($Context.Data.HighValueApps)) {
        $AppId = "$($App.appId)"
        $IsCovered = @($Context.Enabled | Where-Object {
                $Apps = $_.conditions.applications
                $IncludesAll = @($Apps.includeApplications) -contains 'All'
                $IncludesSpecific = @($Apps.includeApplications) -contains $AppId
                $IsExcluded = @($Apps.excludeApplications) -contains $AppId
                $C = @($_.grantControls.builtInControls)
                $HasMfaOrBlock = ($C -contains 'mfa') -or ($C -contains 'block') -or ($null -ne $_.grantControls.authenticationStrength)
                ($IncludesAll -or $IncludesSpecific) -and -not $IsExcluded -and $HasMfaOrBlock
            }).Count -gt 0
        if (-not $IsCovered) { $Unprotected.Add($App) }
    }

    if ($Unprotected.Count -gt 0) {
        $CriticalApps = @($Unprotected | Where-Object { $_.risk -eq 'critical' })
        $AppLines = @($Unprotected | ForEach-Object { "- $($_.name) ($($_.description)), $($_.risk) risk" }) -join "`n"
        $CriticalSuffix = if ($CriticalApps.Count -gt 0) { ", $($CriticalApps.Count) of them critical" } else { '' }
        $Params = @{
            Severity         = if ($CriticalApps.Count -gt 0) { 'Critical' } else { 'High' }
            Category         = 'Application coverage'
            Title            = "$($Unprotected.Count) high-value Microsoft service(s) can be reached with a password alone$CriticalSuffix"
            Description      = "No enforced policy requires multifactor authentication or blocks access for these services, which hold the tenant's most sensitive data and controls:`n$AppLines`n`nA stolen password is enough to manage Azure resources, read mail and files through the API, or open mailboxes and documents directly."
            Remediation      = 'Require multifactor authentication from all users for all applications as the baseline, and add stricter requirements such as phishing-resistant methods for Azure management.'
            RelatedIds       = @($Unprotected | ForEach-Object { "$($_.appId)" })
            CaTemplate       = "$($Context.Data.Reference.templates.mfaAllUsers)"
            DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/policy-all-users-mfa-strength'
        }
        $Findings.Add((New-CIPPCAGapFinding @Params))
    }

    @($Findings)
}

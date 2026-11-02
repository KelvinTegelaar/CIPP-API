function Test-CIPPCAGapFociExclusion {
    <#
    .SYNOPSIS
        Flags policies that exclude an app from the FOCI (Family of Client IDs) token-sharing family.
    .DESCRIPTION
        FOCI apps share refresh tokens, so excluding one Microsoft client (Teams, Office, Outlook Mobile,
        ...) from a policy effectively excludes every other family member.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $Findings = [System.Collections.Generic.List[object]]::new()
    $FociApps = @($Context.Data.FociApps)

    foreach ($Policy in @($Context.Policies)) {
        foreach ($AppId in @($Policy.conditions.applications.excludeApplications)) {
            $Key = "$AppId".ToLowerInvariant()
            $App = $Context.Data.FociById[$Key]
            if ($null -eq $App) { continue }

            $Family = @($FociApps | Where-Object { "$($_.appId)".ToLowerInvariant() -ne $Key })
            $FamilyNames = @($Family | Select-Object -First 8 | ForEach-Object { "$($_.displayName)" })
            $Overflow = if ($Family.Count -gt 8) { ' and others' } else { '' }

            $Params = @{
                Severity         = 'Critical'
                Category         = 'Shared app tokens'
                Title            = "Exempting $($App.displayName) also exempts $($Family.Count) related Microsoft apps"
                Description      = "$($App.displayName) belongs to a family of Microsoft applications that share sign-in tokens, so a token obtained through one member works for the others. " +
                "Exempting it from this policy therefore exempts the whole family, including $($FamilyNames -join ', ')$Overflow."
                Remediation      = 'Remove the exemption and, if this application needs different treatment, give it a dedicated policy instead of exempting it from a broad one.'
                AffectedPolicies = @($Policy.displayName)
                RelatedIds       = @($Family | ForEach-Object { "$($_.appId)" })
                DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/concept-conditional-access-cloud-apps'
            }
            $Findings.Add((New-CIPPCAGapFinding @Params))
        }
    }

    @($Findings)
}

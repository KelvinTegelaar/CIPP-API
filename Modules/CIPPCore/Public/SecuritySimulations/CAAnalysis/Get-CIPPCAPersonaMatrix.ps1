function Get-CIPPCAPersonaMatrix {
    <#
    .SYNOPSIS
        Builds the "who is protected by what" matrix: four personas by eight controls.
    .DESCRIPTION
        Personas come from how policies TARGET identities, never from policy names, so the matrix is
        truthful for tenants that follow no naming convention: Admins              - policies that include
        privileged roles, or All users without excluding roles Users               - policies that include
        All users (group-scoped policies never prove everyone is covered) Guests              - policies
        that include guests/external users, or All users without excluding them Workload identities -
        policies that include service principals A cell is Enforced when an enabled policy in the persona's
        bucket implements the control, ReportOnly when only a report-only policy does, Missing otherwise,
        NotApplicable when the persona does not need that control, and Unlicensed when the tenant cannot
        implement it: risk-based controls need Entra ID P2, compliant-device controls need Intune,
        workload-identity risk needs Workload Identities Premium - a tenant is never marked as missing a
        control it cannot buy into.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context
    )

    $ControlMeta = $Context.Data.CoverageControls
    $ControlOrder = @('RequireMfa', 'PhishingResistantMfa', 'RequireCompliantDevice', 'BlockLegacyAuth', 'SignInRisk', 'UserRisk', 'SessionControls', 'BlockCountries')
    $Personas = @(
        [PSCustomObject]@{ id = 'admins'; label = 'Admins'; expected = $ControlOrder }
        [PSCustomObject]@{ id = 'users'; label = 'Users'; expected = @($ControlOrder | Where-Object { $_ -ne 'PhishingResistantMfa' }) }
        [PSCustomObject]@{ id = 'guests'; label = 'Guests'; expected = @('RequireMfa', 'BlockLegacyAuth', 'SignInRisk', 'SessionControls', 'BlockCountries') }
        [PSCustomObject]@{ id = 'workloadIdentities'; label = 'Workload identities'; expected = @('SignInRisk', 'BlockCountries') }
    )

    $Licenses = $Context.Licenses
    $Unavailable = [System.Collections.Generic.List[string]]::new()
    if ($Licenses.HasEntraIdP2 -ne $true) { $Unavailable.Add('SignInRisk'); $Unavailable.Add('UserRisk') }
    if ($Licenses.HasIntunePlan1 -ne $true) { $Unavailable.Add('RequireCompliantDevice') }
    $WorkloadRiskAvailable = $Licenses.HasWorkloadIdPremium -eq $true

    $PolicyPersonas = {
        param($P)
        $Out = [System.Collections.Generic.List[string]]::new()
        $U = $P.conditions.users
        $All = @($U.includeUsers) -contains 'All'
        $ExcludesGuests = ($null -ne $U.excludeGuestsOrExternalUsers -and "$($U.excludeGuestsOrExternalUsers.guestOrExternalUserTypes)") -or (@($U.excludeUsers) -contains 'GuestsOrExternalUsers')
        $IncludesGuests = ($null -ne $U.includeGuestsOrExternalUsers -and "$($U.includeGuestsOrExternalUsers.guestOrExternalUserTypes)") -or (@($U.includeUsers) -contains 'GuestsOrExternalUsers')
        if (@($U.includeRoles).Count -gt 0 -or ($All -and @($U.excludeRoles).Count -eq 0)) { $Out.Add('admins') }
        if ($All) { $Out.Add('users') }
        if ($IncludesGuests -or ($All -and -not $ExcludesGuests)) { $Out.Add('guests') }
        if (@($P.conditions.clientApplications.includeServicePrincipals).Count -gt 0) { $Out.Add('workloadIdentities') }
        $Out.ToArray()
    }

    $Detectors = @{
        'BlockLegacyAuth'        = {
            param($P)
            $Types = @($P.conditions.clientAppTypes)
            (($Types -contains 'exchangeActiveSync') -or ($Types -contains 'other')) -and (@($P.grantControls.builtInControls) -contains 'block')
        }
        'RequireMfa'              = {
            param($P)
            (@($P.grantControls.builtInControls) -contains 'mfa') -or (-not [string]::IsNullOrWhiteSpace("$($P.grantControls.authenticationStrength.id)"))
        }
        'RequireCompliantDevice' = {
            param($P)
            $C = @($P.grantControls.builtInControls)
            ($C -contains 'compliantDevice') -or ($C -contains 'domainJoinedDevice')
        }
        'SignInRisk'             = {
            param($P)
            (@($P.conditions.signInRiskLevels).Count -gt 0) -or (@($P.conditions.servicePrincipalRiskLevels).Count -gt 0)
        }
        'UserRisk'                = { param($P) @($P.conditions.userRiskLevels).Count -gt 0 }
        'SessionControls'              = {
            param($P)
            ($P.sessionControls.signInFrequency.isEnabled -eq $true) -or ($P.sessionControls.persistentBrowser.isEnabled -eq $true)
        }
        'BlockCountries'          = {
            param($P)
            $L = $P.conditions.locations
            ($null -ne $L) -and ((@($L.includeLocations).Count -gt 0) -or (@($L.excludeLocations).Count -gt 0)) -and (@($P.grantControls.builtInControls) -contains 'block')
        }
        'PhishingResistantMfa'   = { param($P) Test-CIPPCAPolicyPhishingResistant -Policy $P -Context $Context }
    }

    $SeverityForGap = {
        param($PersonaId, $Control)
        switch ($PersonaId) {
            'admins' { if ($Control -in @('RequireMfa', 'PhishingResistantMfa')) { 'Critical' } else { 'High' } }
            'users' { if ($Control -eq 'RequireMfa') { 'Critical' } elseif ($Control -eq 'BlockLegacyAuth') { 'High' } else { 'Medium' } }
            'guests' { if ($Control -eq 'RequireMfa') { 'High' } else { 'Medium' } }
            default { 'Low' }
        }
    }

    $Buckets = @{}
    foreach ($Persona in $Personas) { $Buckets[$Persona.id] = [System.Collections.Generic.List[object]]::new() }
    foreach ($Policy in @($Context.Policies)) {
        foreach ($PersonaId in @(& $PolicyPersonas $Policy)) {
            $Buckets[$PersonaId].Add($Policy)
        }
    }

    $Cells = [System.Collections.Generic.List[object]]::new()
    $Findings = [System.Collections.Generic.List[object]]::new()

    foreach ($Persona in $Personas) {
        $Assigned = @($Buckets[$Persona.id])
        foreach ($Control in $ControlOrder) {
            $ControlLabel = "$($ControlMeta.$Control.label)"
            if ($Persona.expected -notcontains $Control) {
                $Cells.Add([PSCustomObject]@{ persona = $Persona.label; control = $ControlLabel; state = 'NotApplicable'; policies = [string[]]@() })
                continue
            }
            $Unlicensed = ($Unavailable -contains $Control) -or ($Persona.id -eq 'workloadIdentities' -and $Control -eq 'SignInRisk' -and -not $WorkloadRiskAvailable)
            if ($Unlicensed) {
                $Cells.Add([PSCustomObject]@{ persona = $Persona.label; control = $ControlLabel; state = 'Unlicensed'; policies = [string[]]@() })
                continue
            }
            $Detector = $Detectors[$Control]
            $EnabledHits = [string[]]@($Assigned | Where-Object { $_.state -eq 'enabled' -and (& $Detector $_) } | ForEach-Object { "$($_.displayName)" })
            $ReportOnlyHits = [string[]]@($Assigned | Where-Object { $_.state -eq 'enabledForReportingButNotEnforced' -and (& $Detector $_) } | ForEach-Object { "$($_.displayName)" })

            if ($EnabledHits.Count -gt 0) {
                $State = 'Enforced'; $Names = $EnabledHits
            } elseif ($ReportOnlyHits.Count -gt 0) {
                $State = 'ReportOnly'; $Names = $ReportOnlyHits
            } else {
                $State = 'Missing'; $Names = [string[]]@()
            }
            $Cells.Add([PSCustomObject]@{ persona = $Persona.label; control = $ControlLabel; state = $State; policies = $Names })

            if ($State -eq 'Missing' -and $Persona.id -ne 'workloadIdentities') {
                $Params = @{
                    Severity         = & $SeverityForGap $Persona.id $Control
                    Category         = 'Persona coverage'
                    Title            = "$($Persona.label) have no enforced policy for ""$ControlLabel"""
                    Description      = "None of the enforced policies that apply to $($Persona.label) provides this control. $($ControlMeta.$Control.description)"
                    Remediation      = "Extend a policy that already applies to $($Persona.label) with this control, or add a dedicated one."
                    CaTemplate       = "$ControlLabel for $($Persona.label)"
                    DocumentationUrl = 'https://learn.microsoft.com/entra/identity/conditional-access/concept-conditional-access-policy-common'
                }
                $Findings.Add((New-CIPPCAGapFinding @Params))
            }
        }
    }

    [PSCustomObject]@{
        personas     = [string[]]@($Personas | ForEach-Object { $_.label })
        controls     = [string[]]@($ControlOrder | ForEach-Object { "$($ControlMeta.$_.label)" })
        cells        = @($Cells)
        findings     = @($Findings)
    }
}

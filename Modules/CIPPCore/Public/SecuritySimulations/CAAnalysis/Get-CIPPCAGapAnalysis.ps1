function Get-CIPPCAGapAnalysis {
    <#
    .SYNOPSIS
        Runs the Conditional Access gap analysis for one tenant from CIPP's cache.
    .DESCRIPTION
        Builds the shared context (Get-CIPPCAAnalysisContext, cache only - no Graph calls), runs every
        Test-CIPPCAGap* check, adds the persona-coverage findings, builds the persona x control matrix and
        returns one object: policyCount, enabledCount, reportOnlyCount, disabledCount, findings      = @( id
        (F-0001...), title, severity (Critical|High|Medium|Low|Info), category, description,
        affectedPolicies (display names), remediation, fix ($null or @{ caTemplate }), relatedIds ),
        personaMatrix = @{ personas; controls; cells = @( persona, control, state
        (Enforced|ReportOnly|Missing|NotApplicable), policies ) }, score         = @{ score (1-10), scoreMax
        = 10, enforcedControls, applicableControls, criticalFindings, highFindings }, licenses, breakGlass.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $Context = Get-CIPPCAAnalysisContext -TenantFilter $TenantFilter

    $Checks = @(
        'Test-CIPPCAGapFociExclusion'
        'Test-CIPPCAGapSwissCheeseGrant'
        'Test-CIPPCAGapDeviceRegistrationBypass'
        'Test-CIPPCAGapKnownBypassApps'
        'Test-CIPPCAGapMissingMfa'
        'Test-CIPPCAGapReportOnlyState'
        'Test-CIPPCAGapResilienceDefaults'
        'Test-CIPPCAGapLocationConditions'
        'Test-CIPPCAGapLegacyAuth'
        'Test-CIPPCAGapUserAgentBypass'
        'Test-CIPPCAGapMicrosoftManagedPolicy'
        'Test-CIPPCAGapPrivilegedRoleExclusion'
        'Test-CIPPCAGapGuestExclusion'
        'Test-CIPPCAGapCredentialRegistration'
        'Test-CIPPCAGapGuestAuthStrength'
        'Test-CIPPCAGapProtectedActions'
        'Test-CIPPCAGapBreakGlass'
        'Test-CIPPCAGapMfaCoverage'
        'Test-CIPPCAGapIdentityProtection'
        'Test-CIPPCAGapHighValueApps'
        'Test-CIPPCAGapCaImmuneResources'
        'Test-CIPPCAGapResourceExclusionBypass'
        'Test-CIPPCAGapUncoveredAppExclusions'
        'Test-CIPPCAGapMicrosoftGuidance'
    )

    $Findings = [System.Collections.Generic.List[object]]::new()
    foreach ($Check in $Checks) {
        try {
            foreach ($Finding in @(& $Check -Context $Context -ErrorAction Stop)) {
                if ($null -ne $Finding) { $Findings.Add($Finding) }
            }
        } catch {
            Write-Information "Get-CIPPCAGapAnalysis: $Check failed for $TenantFilter - $($_.Exception.Message)"
        }
    }

    $Persona = Get-CIPPCAPersonaMatrix -Context $Context
    foreach ($Finding in @($Persona.findings)) { $Findings.Add($Finding) }

    $Findings = [System.Collections.Generic.List[object]]@($Findings | Where-Object { "$($_.severity)" -notin @('Info', 'Low') })
    $Sequence = 0
    foreach ($Finding in $Findings) {
        $Sequence++
        $Finding.id = 'F-{0:d4}' -f $Sequence
    }

    $PersonaMatrix = [PSCustomObject]@{
        personas = $Persona.personas
        controls = $Persona.controls
        cells    = @($Persona.cells)
    }
    $Score = Get-CIPPCAPostureScore -Findings @($Findings) -PersonaMatrix $PersonaMatrix

    [PSCustomObject]@{
        policyCount     = @($Context.Policies).Count
        enabledCount    = @($Context.Enabled).Count
        reportOnlyCount = @($Context.ReportOnly).Count
        disabledCount   = @($Context.Disabled).Count
        findings        = @($Findings)
        personaMatrix   = $PersonaMatrix
        score           = $Score
        licenses        = [PSCustomObject]@{
            source               = "$($Context.Licenses.Source)"
            hasEntraIdP1         = [bool]$Context.Licenses.HasEntraIdP1
            hasEntraIdP2         = [bool]$Context.Licenses.HasEntraIdP2
            hasIntunePlan1       = [bool]$Context.Licenses.HasIntunePlan1
            hasWorkloadIdPremium = [bool]$Context.Licenses.HasWorkloadIdPremium
        }
        breakGlass      = $Context.BreakGlass
    }
}

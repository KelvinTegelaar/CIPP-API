function Invoke-CIPPBaselineExoRequest {
    <#
    .SYNOPSIS
        ExoRequest executor: runs a definition's ordered cmdlets[] against one tenant.
    .DESCRIPTION
        One script for the whole request type - the ordered array supports remediations that
        need several cmdlets (pre-steps first). Each entry is { cmdlet, params,
        continueOnError, compliance }; continueOnError marks idempotent pre-steps such as
        Enable-OrganizationCustomization, which fails when it already ran. compliance routes
        the step through the Security & Compliance endpoint instead of Exchange Online -
        the *-ProtectionAlert, *-DlpCompliance* and *-Retention* cmdlet families only exist
        there, and calling them without it fails with an unrecognised-cmdlet error. The spec
        arrives fully rendered (%var% + tenant tokens resolved).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        # The read result. Unused here; every executor takes the same arguments.
        $Current
    )

    foreach ($Step in @($Remediate.cmdlets)) {
        if (-not $Step) { continue }
        $CmdParams = @{}
        foreach ($Property in ($Step.params ?? [PSCustomObject]@{}).PSObject.Properties) {
            $CmdParams[$Property.Name] = $Property.Value
        }
        try {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet $Step.cmdlet -cmdParams $CmdParams -useSystemMailbox $true -Compliance:([bool]($Step.compliance ?? $false))
        } catch {
            if ($Step.continueOnError -eq $true) {
                Write-Information "Baselines: $($Step.cmdlet) on $TenantFilter continued past: $($_.Exception.Message)"
            } else { throw }
        }
    }
}

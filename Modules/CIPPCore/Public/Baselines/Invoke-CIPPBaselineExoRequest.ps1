function Invoke-CIPPBaselineExoRequest {
    <#
    .SYNOPSIS
        ExoRequest executor: runs a definition's ordered cmdlets[] against one tenant.
    .DESCRIPTION
        One script for the whole request type - the ordered array supports remediations that
        need several cmdlets (pre-steps first). Each entry is { cmdlet, params,
        continueOnError }; continueOnError marks idempotent pre-steps such as
        Enable-OrganizationCustomization, which fails when it already ran. The spec arrives
        fully rendered (%var% + tenant tokens resolved).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter
    )

    foreach ($Step in @($Remediate.cmdlets)) {
        if (-not $Step) { continue }
        $CmdParams = @{}
        foreach ($Property in ($Step.params ?? [PSCustomObject]@{}).PSObject.Properties) {
            $CmdParams[$Property.Name] = $Property.Value
        }
        try {
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet $Step.cmdlet -cmdParams $CmdParams -useSystemMailbox $true
        } catch {
            if ($Step.continueOnError -eq $true) {
                Write-Information "Baselines: $($Step.cmdlet) on $TenantFilter continued past: $($_.Exception.Message)"
            } else { throw }
        }
    }
}

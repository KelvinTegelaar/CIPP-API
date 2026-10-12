function Invoke-CIPPBaselineAuthenticationMethods {
    <#
    .SYNOPSIS
        AuthenticationMethods executor: writes every drifted method's configuration.
    .DESCRIPTION
        One Set-CIPPAuthenticationPolicy call per parameter set the hook carried - the
        shared helper the classic and the identity UI use, which owns the per-method PATCH
        shapes. Only drifted methods write; compliant ones are never touched. Partial
        failures log and continue so one method's error cannot block the rest; a round
        where every method failed throws.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Remediate,
        $TenantFilter,
        $Current
    )

    $Sets = @($Current.remediationSets | Where-Object { $_ })
    if ($Sets.Count -eq 0) { return }

    $Failures = 0
    foreach ($Set in $Sets) {
        try {
            # The hook carries the parameter set as a hashtable in-process; a JSON round-trip
            # (resume, serialization) would hand it back as a PSCustomObject - accept both.
            $Params = @{ Tenant = $TenantFilter; APIName = 'Baselines' }
            if ($Set.Params -is [hashtable]) {
                foreach ($Key in $Set.Params.Keys) { $Params[$Key] = $Set.Params[$Key] }
            } else {
                foreach ($Property in $Set.Params.PSObject.Properties) { $Params[$Property.Name] = $Property.Value }
            }
            $null = Set-CIPPAuthenticationPolicy @Params
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Applied the $($Set.Label) authentication method configuration." -Sev 'Info'
        } catch {
            $Failures++
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Authentication method write failed for $($Set.Label): $($_.Exception.Message)" -Sev 'Error'
        }
    }
    if ($Failures -ge $Sets.Count) { throw "Every authentication method write failed for $TenantFilter - see the log for the first error." }
}

function Invoke-CIPPBaselineGraphRequest {
    <#
    .SYNOPSIS
        GraphRequest executor: runs a definition's ordered requests[] against one tenant.
    .DESCRIPTION
        One script for the whole request type - the ordered array supports remediations that
        need several Graph calls. Each entry is { method (PATCH/POST/PUT), uri (relative to
        the beta endpoint), body, continueOnError, asApp }. The spec arrives fully rendered
        (%var% + tenant tokens resolved). asApp defaults to true (app-only); a step sets
        asApp: false where the SAM app holds the permission only as a delegated scope -
        e.g. Policy.ReadWrite.Authorization, so every authorizationPolicy write must go
        delegated or Graph returns 403.
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

    foreach ($Step in @($Remediate.requests)) {
        if (-not $Step) { continue }
        $Method = $Step.method ?? 'PATCH'
        if ($Method -eq 'PATCH' -and @(($Step.body ?? [PSCustomObject]@{}).PSObject.Properties).Count -eq 0) {
            Write-Information "Baselines: PATCH $($Step.uri) on $TenantFilter skipped - nothing configured to write."
            continue
        }
        try {
            $null = New-GraphPostRequest -tenantid $TenantFilter -uri "https://graph.microsoft.com/beta/$($Step.uri)" -type $Method -body (ConvertTo-Json -Compress -Depth 100 -InputObject $Step.body) -AsApp ([bool]($Step.asApp ?? $true))
        } catch {
            if ($Step.continueOnError -eq $true) {
                Write-Information "Baselines: $Method $($Step.uri) on $TenantFilter continued past: $($_.Exception.Message)"
            } else { throw }
        }
    }
}

function Start-TokenWarmupTimer {
    <#
    .SYNOPSIS
    Warm up Graph tokens for all tenants
    .DESCRIPTION
    Iterates through all active tenants and acquires a Graph token for each one,
    populating the in-memory token cache so subsequent API calls hit the fast path.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    if ($PSCmdlet.ShouldProcess('Start-TokenWarmupTimer', 'Starting Token Warmup Timer')) {
        $TenantList = Get-Tenants -IncludeErrors
        Write-LogMessage -API 'TokenWarmup' -message "Starting token warmup for $($TenantList.Count) tenants" -sev Info

        $SuccessCount = 0
        $FailCount = 0
        foreach ($Tenant in $TenantList) {
            try {
                $null = Get-GraphToken -tenantid $Tenant.customerId -scope 'https://graph.microsoft.com/.default'
                $SuccessCount++
            } catch {
                $FailCount++
                Write-LogMessage -API 'TokenWarmup' -tenant $Tenant.defaultDomainName -message "Token warmup failed: $($_.Exception.Message)" -sev Debug
            }
        }

        Write-LogMessage -API 'TokenWarmup' -message "Token warmup complete: $SuccessCount succeeded, $FailCount failed out of $($TenantList.Count) tenants" -sev Info
    }
}

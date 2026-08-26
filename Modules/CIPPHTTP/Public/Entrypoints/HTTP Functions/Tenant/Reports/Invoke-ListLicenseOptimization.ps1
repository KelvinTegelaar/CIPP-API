function Invoke-ListLicenseOptimization {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Directory.Read
    .DESCRIPTION
        License cost-optimization report for a tenant: a monetary summary plus reclaim
        opportunities across five waste tiers (unassigned seats, disabled and inactive licensed
        accounts, mailbox-only downgrade candidates, and redundant overlapping SKUs). Computed from
        the reporting-DB cache. For tenantFilter=AllTenants it returns a per-tenant summary money
        map (ranked by reclaimable spend) instead of the full opportunity detail.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # The tenant to report on, or AllTenants for the cross-tenant summary money map
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    # Sign-in age in days past which an enabled licensed user counts as inactive (default 90)
    $InactiveDays = ($Request.Query.inactiveDays ?? $Request.Body.inactiveDays) -as [int]
    if (-not $InactiveDays -or $InactiveDays -le 0) { $InactiveDays = 90 }
    # Currency the money figures are resolved in (ISO code); defaults to USD
    $Currency = $Request.Query.currency ?? $Request.Body.currency
    if ([string]::IsNullOrWhiteSpace($Currency)) { $Currency = 'USD' }

    try {
        if ($TenantFilter -eq 'AllTenants') {
            $Summaries = [System.Collections.Generic.List[object]]::new()
            foreach ($Tenant in (Get-Tenants -IncludeErrors)) {
                try {
                    $Report = Get-CIPPLicenseOptimization -TenantFilter $Tenant.defaultDomainName -InactiveDays $InactiveDays -Currency $Currency
                    if ($Report.Summary.DataAvailable) { $Summaries.Add($Report.Summary) }
                } catch {
                    Write-Information "License optimization failed for $($Tenant.defaultDomainName): $($_.Exception.Message)"
                }
            }
            $Results = @($Summaries | Sort-Object -Property ReclaimableMonthly -Descending)
        } else {
            if ([string]::IsNullOrWhiteSpace($TenantFilter)) { throw 'tenantFilter is required.' }
            $Results = Get-CIPPLicenseOptimization -TenantFilter $TenantFilter -InactiveDays $InactiveDays -Currency $Currency
        }
        $StatusCode = [System.Net.HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $StatusCode = [System.Net.HttpStatusCode]::InternalServerError
        $Results = "Failed to build license optimization report. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API $APIName -headers $Headers -message $Results -Sev 'Error' -LogData $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = [pscustomobject]@{ 'Results' = $Results }
        })
}

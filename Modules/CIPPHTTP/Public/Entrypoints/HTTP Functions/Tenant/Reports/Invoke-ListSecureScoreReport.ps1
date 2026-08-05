function Invoke-ListSecureScoreReport {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Reports.Read
    .DESCRIPTION
        Returns the latest Microsoft Secure Score per tenant from the CIPP reporting database, with no
        live Graph calls. Reads the nightly cache and projects to the score fields only, so the large
        controlScores breakdown on each cached record is never materialized.

        Query parameters:
          - tenantFilter: A tenant domain, or 'AllTenants' for every tenant the caller can see.
          - includeHistory: When 'true', each tenant also carries a History array of the retained
                            daily scores (date / score / percentage) for trend display.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $TenantFilter = $Request.Query.tenantFilter ?? 'AllTenants'
    $IncludeHistory = $Request.Query.includeHistory -eq $true

    try {
        $Results = @(Get-CIPPSecureScoreReport -TenantFilter $TenantFilter -IncludeHistory:$IncludeHistory)

        # AnyTenant is set so AllTenants is reachable, which means the framework's per-tenant check is
        # skipped for custom-role users. Scope the output here instead, for both paths.
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        if ($AllowedTenants -notcontains 'AllTenants') {
            $AllowedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($Allowed in $AllowedTenants) {
                if ($Allowed) { [void]$AllowedSet.Add([string]$Allowed) }
            }
            $Results = @($Results | Where-Object { $_.TenantId -and $AllowedSet.Contains([string]$_.TenantId) })
        }

        $StatusCode = [HttpStatusCode]::OK
        $Body = @{ Results = @($Results) }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to retrieve secure score report: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
        $Body = @{ Error = $ErrorMessage.NormalizedError }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

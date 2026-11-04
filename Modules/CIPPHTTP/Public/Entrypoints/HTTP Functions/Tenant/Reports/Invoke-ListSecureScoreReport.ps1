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
          - includeControls: When 'true', each tenant also carries its per-control scores and states
                             as Controls, and the response adds a Catalog of shared control metadata.
          - ControlName: With a single tenantFilter, returns that tenant's cached control profile
                         (description, remediation, state history) instead of the report.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $TenantFilter = $Request.Query.tenantFilter ?? 'AllTenants'
    $IncludeHistory = $Request.Query.includeHistory -eq $true
    $IncludeControls = $Request.Query.includeControls -eq $true
    $ControlName = $Request.Query.ControlName

    # AnyTenant is set so AllTenants is reachable, which means the framework's per-tenant check is
    # skipped for custom-role users. Scope the output here instead, for both paths.
    try {
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
    } catch {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::Forbidden
                Body       = @{ Error = $_.Exception.Message }
            })
    }

    $AllowedSet = $null
    if ($AllowedTenants -notcontains 'AllTenants') {
        $AllowedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Allowed in $AllowedTenants) {
            if ($Allowed) { [void]$AllowedSet.Add([string]$Allowed) }
        }
    }

    try {
        if ($ControlName) {
            # One tenant's cached control profile (description, remediation, state history) for the
            # detail dialog. Kept out of the report rows because that HTML is the bulk of each profile.
            $Tenant = if ($TenantFilter -ne 'AllTenants') { Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1 }
            if ($ControlName -notmatch '^[A-Za-z0-9_.-]+$' -or -not $Tenant) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ Error = 'ControlName needs a valid control id and a single managed tenantFilter' }
                    })
            }
            if ($AllowedSet -and -not $AllowedSet.Contains([string]$Tenant.customerId)) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::Forbidden
                        Body       = @{ Error = 'You do not have access to this tenant' }
                    })
            }

            # Same key Add-CIPPDbItem writes; the range keeps a split ('-partN') row reassemblable.
            $RowKey = ConvertTo-CIPPODataFilterValue -Value "SecureScoreControlProfiles-$ControlName" -Type String
            $Partition = ConvertTo-CIPPODataFilterValue -Value $Tenant.defaultDomainName -Type String
            $Table = Get-CippTable -tablename 'CippReportingDB'
            $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$Partition' and RowKey ge '$RowKey' and RowKey lt '$RowKey.'" |
                Where-Object { $_.RowKey -eq "SecureScoreControlProfiles-$ControlName" } | Select-Object -First 1

            $StatusCode = [HttpStatusCode]::OK
            $Body = @{ Results = if ($Row.Data) { [CIPP.CippJson]::ConvertFromJson($Row.Data, $null) } else { $null } }
        } else {
            $Report = Get-CIPPSecureScoreReport -TenantFilter $TenantFilter -IncludeHistory:$IncludeHistory -IncludeControls:$IncludeControls
            $Results = @($IncludeControls ? $Report.Results : $Report)
            if ($AllowedSet) {
                $Results = @($Results | Where-Object { $_.TenantId -and $AllowedSet.Contains([string]$_.TenantId) })
            }

            $StatusCode = [HttpStatusCode]::OK
            $Body = @{ Results = @($Results) }
            if ($IncludeControls) { $Body.Catalog = $Report.Catalog }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to retrieve secure score report: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Body = @{ Error = $ErrorMessage.NormalizedError }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

function Invoke-ListServiceHealthIssues {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Administration.Read
    .DESCRIPTION
        Lists Microsoft 365 service health issues for a tenant: the incidents and advisories Microsoft has posted about service outages, degradations and their status, impact, affected services and timeline. For AllTenants each issue is returned once with the tenants it affects (Tenants, TenantCount). Supports UseReportDB=true query parameter to retrieve cached data from the reporting database for significantly better performance, especially when querying AllTenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter
    # Serve from the reporting database cache instead of live Graph. Much faster, especially for AllTenants.
    $UseReportDB = $Request.Query.UseReportDB -eq $true

    if ($TenantFilter -eq 'AllTenants' -or $UseReportDB) {
        try {
            $DbTenant = if ($TenantFilter -eq 'AllTenants') { 'allTenants' } else { $TenantFilter }
            $RowsByTenant = Get-CIPPDbItem -TenantFilter $DbTenant -Type 'ServiceHealthIssues' -ByTenant
            if ($RowsByTenant.Count -eq 0) {
                throw "No service health issues data found for $TenantFilter. Run a cache sync first."
            }
            # The same Microsoft issue is posted to every tenant, so AllTenants returns each once with the tenants it reached
            $ById = [ordered]@{}
            foreach ($Tenant in $RowsByTenant.Keys) {
                foreach ($Row in $RowsByTenant[$Tenant]) {
                    $Parsed = try { [CIPP.CippJson]::ConvertFromJson($Row.Data, $null) } catch { continue }
                    foreach ($Record in @($Parsed)) {
                        $Entry = $ById[$Record.id]
                        if (-not $Entry) {
                            $Entry = @{ Record = $Record; Tenants = [System.Collections.Generic.List[string]]::new(); Details = [System.Collections.Generic.List[object]]::new(); CacheTimestamp = $Row.Timestamp }
                            $ById[$Record.id] = $Entry
                        } elseif ($Record.lastModifiedDateTime -gt $Entry.Record.lastModifiedDateTime) {
                            $Entry.Record = $Record
                        }
                        if ($Row.Timestamp -gt $Entry.CacheTimestamp) { $Entry.CacheTimestamp = $Row.Timestamp }
                        $Entry.Tenants.Add($Tenant)
                        # details is the one tenant-specific part (workloads affected, feature rollout state)
                        $Entry.Details.Add([pscustomobject]@{ Tenant = $Tenant; details = $Record.details })
                    }
                }
            }
            $Results = foreach ($Entry in $ById.Values) {
                $Properties = $Entry.Record.PSObject.Properties
                $Properties.Add([psnoteproperty]::new('CacheTimestamp', $Entry.CacheTimestamp))
                if ($TenantFilter -eq 'AllTenants') {
                    $Count = $Entry.Tenants.Count
                    $Properties.Add([psnoteproperty]::new('Tenants', [string[]]$Entry.Tenants))
                    $Properties.Add([psnoteproperty]::new('TenantCount', $Count))
                    $Properties.Add([psnoteproperty]::new('TenantDetails', $Entry.Details.ToArray()))
                    $Properties.Add([psnoteproperty]::new('Tenant', $(if ($Count -eq 1) { $Entry.Tenants[0] } else { '{0} tenants' -f $Count })))
                }
                $Entry.Record
            }
            $StatusCode = [HttpStatusCode]::OK
        } catch {
            $StatusCode = [HttpStatusCode]::InternalServerError
            $Results = $_.Exception.Message
        }
        return ([HttpResponseContext]@{
                StatusCode = $StatusCode
                Body       = @($Results)
            })
    }

    try {
        $Results = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/issues' -tenantid $TenantFilter
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to retrieve service health issues: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $Results = @()
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })
}

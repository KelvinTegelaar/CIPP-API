function Invoke-ListServiceHealthOverviews {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Administration.Read
    .DESCRIPTION
        Lists the Microsoft 365 service health overview for a tenant: the current health status of each cloud service (Exchange Online, SharePoint Online, Microsoft Teams, Entra ID, Intune and others), for example serviceOperational, serviceDegradation or serviceInterruption. Supports UseReportDB=true query parameter to retrieve cached data from the reporting database for significantly better performance, especially when querying AllTenants.
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
            $RowsByTenant = Get-CIPPDbItem -TenantFilter $DbTenant -Type 'ServiceHealthOverviews' -ByTenant
            if ($RowsByTenant.Count -eq 0) {
                throw "No service health overviews data found for $TenantFilter. Run a cache sync first."
            }
            $Results = foreach ($Tenant in $RowsByTenant.Keys) {
                foreach ($Row in $RowsByTenant[$Tenant]) {
                    $Parsed = try { [CIPP.CippJson]::ConvertFromJson($Row.Data, $null) } catch { continue }
                    foreach ($Record in @($Parsed)) {
                        $Properties = $Record.PSObject.Properties
                        $Properties.Add([psnoteproperty]::new('CacheTimestamp', $Row.Timestamp))
                        if ($TenantFilter -eq 'AllTenants') { $Properties.Add([psnoteproperty]::new('Tenant', $Tenant)) }
                        $Record
                    }
                }
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
        $Results = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/healthOverviews' -tenantid $TenantFilter
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to retrieve service health overviews: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        $Results = @()
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })
}

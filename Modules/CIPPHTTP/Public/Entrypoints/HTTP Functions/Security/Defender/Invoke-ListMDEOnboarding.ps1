function Invoke-ListMDEOnboarding {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.Defender.Read
    .DESCRIPTION
        Lists Microsoft Defender for Endpoint onboarding status for devices in a tenant. Supports UseReportDB=true query parameter to retrieve cached data from the reporting database for significantly better performance. Automatically uses the reporting database when querying AllTenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Query.tenantFilter
    # Serve from the reporting database cache instead of live Graph. Much faster, especially for AllTenants.
    $UseReportDB = $Request.Query.UseReportDB -eq $true
    if ($TenantFilter -eq 'AllTenants') {
        $UseReportDB = 'true'
    }

    try {
        if ($UseReportDB) {
            try {
                # Return one page per request as { Results, Metadata } with a continuation token in Metadata.nextLink.
                if ($Request.Query.manualPagination -eq $true) {
                    # Cached rows per page, clamped between 250 and 10000. Defaults to 5000. Pages hold whole tenants.
                    $PageSize = $Request.Query.PageSize -as [int]
                    return ([HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::OK
                            # Continuation token from the previous page's Metadata.nextLink; opaque to callers.
                            Body       = Get-CIPPReportPage -TenantFilter $TenantFilter -Type 'MDEOnboarding' -PageSize $PageSize -ContinuationToken $Request.Query.nextLink -Report { param($Tenant) Get-CIPPMDEOnboardingReport -TenantFilter $Tenant -ErrorAction Stop }
                        })
                }
                $GraphRequest = Get-CIPPMDEOnboardingReport -TenantFilter $TenantFilter -ErrorAction Stop
                $StatusCode = [HttpStatusCode]::OK
            } catch {
                Write-Host "Error retrieving MDE onboarding status from report database: $($_.Exception.Message)"
                $StatusCode = [HttpStatusCode]::InternalServerError
                $GraphRequest = $_.Exception.Message
            }

            return ([HttpResponseContext]@{
                    StatusCode = $StatusCode
                    Body       = @($GraphRequest)
                })
        }

        $ConnectorId = 'fc780465-2017-40d4-a0c5-307022471b92'
        $ConnectorUri = "https://graph.microsoft.com/beta/deviceManagement/mobileThreatDefenseConnectors/$ConnectorId"
        try {
            $ConnectorState = New-GraphGetRequest -uri $ConnectorUri -tenantid $TenantFilter
            $GraphRequest = $ConnectorState | Select-Object -ExcludeProperty '@odata.context'
            $GraphRequest | Add-Member -NotePropertyName 'Tenant' -NotePropertyValue $TenantFilter -Force
        } catch {
            $GraphRequest = [PSCustomObject]@{
                Tenant       = $TenantFilter
                partnerState = 'unavailable'
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
        $GraphRequest = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })
}

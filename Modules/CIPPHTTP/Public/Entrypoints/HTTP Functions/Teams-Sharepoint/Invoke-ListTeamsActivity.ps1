Function Invoke-ListTeamsActivity {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Teams.Activity.Read
    .DESCRIPTION
        Lists Microsoft Teams user activity reports for a tenant. Supports UseReportDB=true query parameter to retrieve cached data from the reporting database for significantly better performance, especially when querying AllTenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $type = $request.Query.Type
    # Serve from the reporting database cache instead of live Graph. Much faster, especially for AllTenants.
    $UseReportDB = $Request.Query.UseReportDB -eq $true
    if ($TenantFilter -eq 'AllTenants' -or $UseReportDB) {
        try {
            # Return one page per request as { Results, Metadata } with a continuation token in Metadata.nextLink.
            if ($Request.Query.manualPagination -eq $true) {
                # Cached rows per page, clamped between 250 and 10000. Defaults to 5000. Pages hold whole tenants.
                $PageSize = $Request.Query.PageSize -as [int]
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::OK
                        # Continuation token from the previous page's Metadata.nextLink; opaque to callers.
                        Body       = Get-CIPPReportPage -TenantFilter $TenantFilter -Type "TeamsActivity$type" -PageSize $PageSize -ContinuationToken $Request.Query.nextLink -Report { param($Tenant) Get-CIPPTeamsActivityReport -TenantFilter $Tenant -Type $type -ErrorAction Stop }
                    })
            }
            $GraphRequest = Get-CIPPTeamsActivityReport -TenantFilter $TenantFilter -Type $type -ErrorAction Stop
            $StatusCode = [HttpStatusCode]::OK
        } catch {
            $StatusCode = [HttpStatusCode]::InternalServerError
            $GraphRequest = $_.Exception.Message
        }
        return ([HttpResponseContext]@{
                StatusCode = $StatusCode
                Body       = @($GraphRequest)
            })
    }

    $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/reports/get$($type)Detail(period='D30')" -tenantid $TenantFilter | ConvertFrom-Csv | Select-Object @{ Name = 'UPN'; Expression = { $_.'User Principal Name' } },
    @{ Name = 'LastActive'; Expression = { $_.'Last Activity Date' } },
    @{ Name = 'TeamsChat'; Expression = { $_.'Team Chat Message Count' } },
    @{ Name = 'CallCount'; Expression = { $_.'Call Count' } },
    @{ Name = 'MeetingCount'; Expression = { $_.'Meeting Count' } }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($GraphRequest)
        })

}

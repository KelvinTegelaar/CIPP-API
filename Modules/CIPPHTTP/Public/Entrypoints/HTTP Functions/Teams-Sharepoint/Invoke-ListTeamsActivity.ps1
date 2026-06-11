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
    $UseReportDB = $Request.Query.UseReportDB

    if ($TenantFilter -eq 'AllTenants' -or $UseReportDB -eq 'true') {
        try {
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

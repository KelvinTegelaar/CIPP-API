function Invoke-ListTenantAllowBlockList {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SpamFilter.Read
    .DESCRIPTION
        Lists Tenant Allow/Block List entries (senders, URLs, file hashes, IPs) from Exchange Online Protection. Supports UseReportDB=true query parameter to retrieve cached data from the reporting database for significantly better performance, especially when querying AllTenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    # Serve from the reporting database cache instead of live Exchange. Much faster, especially for AllTenants.
    $UseReportDB = $Request.Query.UseReportDB -eq $true

    try {
        # AllTenants has no live path - fanning out to every tenant on request is what the cache is for.
        if ($UseReportDB -or $TenantFilter -eq 'AllTenants') {
            try {
                $Results = Get-CIPPTenantAllowBlockListReport -TenantFilter $TenantFilter -ErrorAction Stop
                $StatusCode = [HttpStatusCode]::OK
            } catch {
                Write-Host "Error retrieving Tenant Allow/Block List from report database: $($_.Exception.Message)"
                $StatusCode = [HttpStatusCode]::InternalServerError
                $Results = $_.Exception.Message
            }

            return ([HttpResponseContext]@{
                    StatusCode = $StatusCode
                    Body       = @($Results)
                })
        }

        # Live Exchange path - every list type in one batched request.
        $Results = foreach ($Entry in @(Get-CIPPTenantAllowBlockListItems -TenantFilter $TenantFilter)) {
            $Entry | Add-Member -MemberType NoteProperty -Name Tenant -Value $TenantFilter -Force
            $Entry
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $Results = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })
}

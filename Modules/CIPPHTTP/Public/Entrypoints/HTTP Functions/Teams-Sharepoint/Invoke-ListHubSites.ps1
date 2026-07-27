function Invoke-ListHubSites {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter

    try {
        if (-not $TenantFilter) { throw 'tenantFilter is required' }

        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
        # Site-level REST: delegated only (no -AsApp)
        $HubSites = New-GraphGETRequest `
            -scope "$($SharePointInfo.SharePointUrl)/.default" `
            -uri "$($SharePointInfo.SharePointUrl)/_api/hubsites" `
            -tenantid $TenantFilter `
            -extraHeaders @{ 'accept' = 'application/json' }

        $Results = @($HubSites | Select-Object ID, Title, SiteUrl)

        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ Results = $Results }
        })
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::InternalServerError
            Body       = @{ Results = "Failed to list hub sites: $ErrorMessage" }
        })
    }
}

Function Invoke-ListSiteMembers {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.TenantFilter
    $SiteId = $Request.Query.SiteId

    try {
        # Find User Information List by template (language independent)
        $Lists = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$SiteId/lists?`$select=id,list,system" -tenantid $TenantFilter -AsApp $true
        $UIList = $Lists | Where-Object { $_.list.template -eq 'userInformation' } | Select-Object -First 1

        if ($UIList.id) {
            $Items = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$SiteId/lists/$($UIList.id)/items?`$expand=fields" -tenantid $TenantFilter -AsApp $true
        } else {
            $Items = @()
        }

        $StatusCode = [HttpStatusCode]::OK
        $Body = @($Items)
    } catch {
        $StatusCode = [HttpStatusCode]::Forbidden
        $Body = Get-NormalizedError -Message $_.Exception.Message
    }

    return ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = @{ 'Results' = $Body }
    })
}

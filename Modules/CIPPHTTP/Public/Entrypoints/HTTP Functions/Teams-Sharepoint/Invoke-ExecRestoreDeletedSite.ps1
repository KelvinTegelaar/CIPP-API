function Invoke-ExecRestoreDeletedSite {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    .DESCRIPTION
        Restores a deleted SharePoint site from the tenant recycle bin via the SharePoint
        admin CSOM API.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $SiteUrl = $Request.Body.SiteUrl ?? $Request.Body.Url

    try {
        if (-not $SiteUrl) { throw 'SiteUrl is required.' }
        $Operation = Restore-CIPPSPODeletedSite -TenantFilter $TenantFilter -SiteUrl $SiteUrl
        $Results = if ($Operation -and -not $Operation.IsComplete) {
            "Restore of $SiteUrl has started. Large sites can take a while to finish restoring."
        } else {
            "Successfully restored $SiteUrl from the tenant recycle bin."
        }
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to restore $($SiteUrl): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Results }
        })
}

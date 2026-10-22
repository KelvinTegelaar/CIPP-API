function Invoke-ListMailboxRules {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    .DESCRIPTION
        Lists inbox rules configured on mailboxes in a tenant, or AllTenants, from the reporting database cache. When manualPagination is set, one page is returned per request as { Results, Metadata } with a continuation token in Metadata.nextLink.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $TenantFilter = $Request.Query.tenantFilter
    try {
        if ($Request.Query.manualPagination -eq $true) {
            # Cached rows per page, clamped between 250 and 10000. Defaults to 5000. Pages hold whole tenants.
            $PageSize = $Request.Query.PageSize -as [int]
            # Continuation token from the previous page's Metadata.nextLink; opaque to callers.
            $Body = Get-CIPPReportPage -TenantFilter $TenantFilter -Type 'MailboxRules' -PageSize $PageSize -ContinuationToken $Request.Query.nextLink -Report { param($Tenant) Get-CIPPMailboxRulesReport -TenantFilter $Tenant -ErrorAction Stop }
        } else {
            $Body = @(Get-CIPPMailboxRulesReport -TenantFilter $TenantFilter -ErrorAction Stop)
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
        $Body = @($_.Exception.Message)
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

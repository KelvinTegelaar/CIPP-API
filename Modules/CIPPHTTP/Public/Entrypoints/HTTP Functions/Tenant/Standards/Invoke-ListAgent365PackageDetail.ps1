function Invoke-ListAgent365PackageDetail {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.Read
    .DESCRIPTION
        Gets the full detail for a single Microsoft Agent 365 / Copilot package by id, including the
        allowedUsersAndGroups, acquireUsersAndGroups and elementDetails that the list endpoint omits.
        Uses delegated auth: this call returns 424 Failed Dependency under application context.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $PackageId = $Request.Query.id ?? $Request.Body.id

    try {
        $Detail = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/copilot/admin/catalog/packages/$PackageId" -tenantid $TenantFilter
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Agent365Packages' -tenant $TenantFilter -message "Could not get Agent 365 package detail for $PackageId. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Detail = [pscustomobject]@{ error = $ErrorMessage.NormalizedError }
        $StatusCode = [HttpStatusCode]::OK
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Detail
        })
}

function Invoke-ListSiteBrowserLibraryCopy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Returns sanitized aggregate status for a SharePoint library copy operation (OperationId).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Query.TenantFilter ?? $Request.Body.tenantFilter ?? $Request.Body.TenantFilter
    $OperationId = $Request.Query.OperationId ?? $Request.Query.operationId ?? $Request.Body.OperationId ?? $Request.Body.operationId
    $StatusCode = [HttpStatusCode]::OK

    try {
        if ([string]::IsNullOrWhiteSpace($TenantFilter)) { throw 'tenantFilter is required.' }
        if ([string]::IsNullOrWhiteSpace($OperationId)) { throw 'OperationId is required.' }

        $Result = Update-CIPPSharePointLibraryCopyStatus -TenantFilter $TenantFilter -OperationId $OperationId
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter `
            -message "Library copy status $OperationId -> $($Result.Status)" -sev Debug
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to retrieve library copy status: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}

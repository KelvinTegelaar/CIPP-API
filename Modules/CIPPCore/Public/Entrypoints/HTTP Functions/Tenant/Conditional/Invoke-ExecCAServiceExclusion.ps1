Function Invoke-ExecCAServiceExclusion {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers


    # Interact with the request
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $ID = $Request.Query.GUID ?? $Request.Body.GUID

    try {
        $result = Set-CIPPCAPolicyServiceException -TenantFilter $TenantFilter -PolicyId $ID
        $Body = @{ Results = $result }
        Write-LogMessage -headers $Headers -API 'Set-CIPPCAPolicyServiceException' -message $Message -Sev 'Info' -tenant $TenantFilter
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Body = @{ Results = "Failed to add service provider exception to policy $($ID): $($ErrorMessage.NormalizedError)" }
        Write-LogMessage -headers $Headers -API 'Set-CIPPCAPolicyServiceException' -message "Failed to update policy $($PolicyId) with service provider exception for tenant $($CSPtenantId): $($_.Exception.Message)" -Sev 'Error' -tenant $TenantFilter -LogData (Get-CippException -Exception $_)
    }

    return ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
}

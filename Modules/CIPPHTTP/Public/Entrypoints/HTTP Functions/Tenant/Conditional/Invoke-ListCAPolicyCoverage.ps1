function Invoke-ListCAPolicyCoverage {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.Read
    .DESCRIPTION
        Resolves identity assignment coverage for a single Conditional Access policy: which users
        are touched by includes or exclusions, their net status (covered or excluded), and why
        (users, transitive groups, roles, guests, special tokens). Does not evaluate apps,
        locations, or sign-in what-if conditions.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $PolicyId = $Request.Query.GUID ?? $Request.Body.GUID ?? $Request.Query.id ?? $Request.Body.id

    if ([string]::IsNullOrWhiteSpace($TenantFilter) -or [string]::IsNullOrWhiteSpace($PolicyId)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'tenantFilter and GUID (policy id) are required.' }
            })
    }

    try {
        $Results = Get-CIPPCAPolicyIdentityCoverage -TenantFilter $TenantFilter -PolicyId $PolicyId
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Resolved identity coverage for CA policy $($Results.displayName)" -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to resolve CA policy coverage: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Results }
        })
}

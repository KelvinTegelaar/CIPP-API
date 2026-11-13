function Invoke-ListBaselineExpiryPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Baselines.Read
    .SYNOPSIS
        Baseline expiry policy
    .DESCRIPTION
        Returns the instance-wide default and maximum expiry, in days, for accepted baseline
        deviations and tenant overrides. 0 means no default or no maximum.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Body = Get-CIPPBaselineExpiryPolicy
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Body = @{ Results = "Failed to read the baseline expiry policy: $($_.Exception.Message)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

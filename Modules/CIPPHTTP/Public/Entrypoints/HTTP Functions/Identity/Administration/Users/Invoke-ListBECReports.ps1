function Invoke-ListBECReports {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Identity.User.Read
    .SYNOPSIS
        Lists Business Email Compromise runs.
    .DESCRIPTION
        Lists every stored BEC run (case id, user, status, threat level and score, when it was extracted, who requested it) for a tenant, or for every tenant with tenantFilter=AllTenants. Optionally narrowed to one user with userId. Runs are kept until deleted; this list never reads the result payloads.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter ?? 'AllTenants'
    # Narrow the list to one user's run history
    $UserId = $Request.Query.userId

    try {
        $Params = @{ TenantFilter = $TenantFilter }
        if ($UserId) { $Params.UserId = $UserId }
        $Runs = @(Get-CIPPBecReport @Params)
        $Body = @($Runs | ForEach-Object {
                [pscustomobject]@{
                    CaseId            = $_.CaseId
                    Tenant            = $_.Tenant
                    UserId            = $_.UserId
                    UserPrincipalName = $_.UserPrincipalName
                    DisplayName       = $_.DisplayName
                    Status            = $_.Status
                    Level             = $_.Level
                    Score             = $_.Score
                    IncompleteCount   = $_.IncompleteCount
                    ExtractedAt       = $_.ExtractedAt
                    RequestedAt       = $_.RequestedAt
                    RequestedBy       = $_.RequestedBy
                    ErrorMessage      = $_.ErrorMessage
                    ContainmentRuns   = @($_.Containment | Where-Object { $_ }).Count
                }
            })
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Body = @{ Results = "Failed to list BEC runs: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

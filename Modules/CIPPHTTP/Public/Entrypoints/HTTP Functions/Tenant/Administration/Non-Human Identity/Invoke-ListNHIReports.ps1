function Invoke-ListNHIReports {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Application.Read
    .SYNOPSIS
        Lists non-human identity (NHI) compromise investigations.
    .DESCRIPTION
        Lists every stored NHI run (case id, app, status, level, evidence level and score, the impact of the app's access, when it was extracted, who requested it) for a tenant, or for every tenant with tenantFilter=AllTenants. Optionally narrowed to one app with servicePrincipalId. Runs are kept until deleted; this list never reads the result payloads.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter ?? 'AllTenants'
    # Narrow the list to one app's run history
    $ServicePrincipalId = $Request.Query.servicePrincipalId

    try {
        $Params = @{ Kind = 'NHI'; TenantFilter = $TenantFilter }
        if ($ServicePrincipalId) { $Params.ServicePrincipalId = $ServicePrincipalId }
        $Runs = @(Get-CIPPBecReport @Params | Select-CippAllowedTenantData -TenantProperty 'Tenant')
        $Body = @($Runs | ForEach-Object {
                [pscustomobject]@{
                    CaseId               = $_.CaseId
                    Tenant               = $_.Tenant
                    ServicePrincipalId   = $_.ServicePrincipalId
                    AppId                = $_.AppId
                    DisplayName          = $_.DisplayName
                    ServicePrincipalType = $_.ServicePrincipalType
                    Status               = $_.Status
                    Level                = $_.Level
                    EvidenceLevel        = $_.EvidenceLevel
                    Impact               = $_.Impact
                    Score                = $_.Score
                    IncompleteCount      = $_.IncompleteCount
                    ExtractedAt          = $_.ExtractedAt
                    RequestedAt          = $_.RequestedAt
                    RequestedBy          = $_.RequestedBy
                    ErrorMessage         = $_.ErrorMessage
                    ContainmentRuns      = @($_.Containment | Where-Object { $_ -and $_.Kind -ne 'Release' }).Count
                }
            })
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Body = @{ Results = "Failed to list NHI runs: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

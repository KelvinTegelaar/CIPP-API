function Invoke-ListAppPermissionExposure {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.Read
    .DESCRIPTION
        Lists the apps (service principals) in one tenant holding permissions from CIPP's risky permissions catalog, with a context-aware risk rating and the impact and suspicion of each permission. UseReportDB=true reads the reporting database; otherwise Graph is read live. ServicePrincipalId returns only that app's row (an empty list when it holds no catalogued permission).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter
    $UseReportDB = $Request.Query.UseReportDB -eq $true
    $ServicePrincipalId = [string]$Request.Query.ServicePrincipalId

    if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'tenantFilter is required' }
            })
    }
    if ($TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'This report covers one tenant at a time. Select a tenant.' }
            })
    }
    $ParsedId = [guid]::Empty
    if ($ServicePrincipalId -and -not [guid]::TryParse($ServicePrincipalId, [ref]$ParsedId)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'ServicePrincipalId must be a GUID' }
            })
    }

    try {
        $Results = @(Get-CIPPAppPermissionExposure -TenantFilter $TenantFilter -Live:(-not $UseReportDB) -ServicePrincipalId $ServicePrincipalId)
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to list app permission exposure: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })
}

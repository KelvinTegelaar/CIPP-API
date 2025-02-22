using namespace System.Net

Function Invoke-ListConditionalAccessPolicyChanges {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.ConditionalAccess.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $PolicyId = $Request.Query.id
    $PolicyDisplayName = $Request.Query.displayName

    try {
        [array]$Changes = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?`$filter=targetResources/any(s:s/id eq '$($PolicyId)')" -tenantid $TenantFilter | ForEach-Object {
            [pscustomobject]@{
                policy           = $PolicyDisplayName
                policyId         = $PolicyId
                typeFriendlyName = $_.activityDisplayName
                type             = $_.operationType
                initiatedBy      = if ($_.initiatedBy.user.userPrincipalName) { $_.initiatedBy.user.userPrincipalName } else { $_.initiatedBy.app.displayName }
                date             = $_.activityDateTime
                oldValue         = ($_.targetResources[0].modifiedProperties.oldValue | ConvertFrom-Json) # targetResources is an array, can we ever get more than 1 object in it?
                newValue         = ($_.targetResources[0].modifiedProperties.newValue | ConvertFrom-Json)
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $StatusCode = [HttpStatusCode]::BadRequest
        $Changes = "Failed to request audit logs for policy $($PolicyDisplayName): $($_.Exception.message)"
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Changes)
        })
}

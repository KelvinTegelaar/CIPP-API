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

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $policyId = $Request.body.id
    $policyDisplayName = $Request.body.displayName

    try {
        [array]$changes = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?`$filter=targetResources/any(s:s/id eq '$($policyId)')" -tenantid $TenantFilter | ForEach-Object {
            [pscustomobject]@{
                policy = $policyDisplayName
                policyId = $policyId
                typeFriendlyName = $_.activityDisplayName
                type = $_.operationType
                initiatedBy = if ($_.initiatedBy.user.userPrincipalName) { $_.initiatedBy.user.userPrincipalName } else { $_.initiatedBy.app.displayName }
                date = $_.activityDateTime
                oldValue = ($_.targetResources[0].modifiedProperties.oldValue | ConvertFrom-Json) # targetResources is an array, can we ever get more than 1 object in it?
                newValue = ($_.targetResources[0].modifiedProperties.newValue | ConvertFrom-Json)
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $StatusCode = [HttpStatusCode]::BadRequest
        Write-Host $($_.Exception.message)
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APIName -message "Failed to request audit logs for policy $($policyDisplayName): $($_.Exception.message)" -Sev "Error" -tenant $TenantFilter
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body       = $changes
    })
}
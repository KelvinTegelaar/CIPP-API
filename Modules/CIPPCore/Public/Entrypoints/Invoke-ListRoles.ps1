using namespace System.Net

Function Invoke-ListRoles {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.TenantFilter
    $SelectList = 'id', 'displayName', 'userPrincipalName'

    [System.Collections.Generic.List[PSCustomObject]]$Roles = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/directoryRoles?`$expand=members" -tenantid $TenantFilter
    $GraphRequest = foreach ($Role in $Roles) {
	
        #[System.Collections.Generic.List[PSCustomObject]]$Members = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/directoryRoles/$($Role.id)/members?`$select=$($selectlist -join ',')" -tenantid $TenantFilter | Select-Object $SelectList
        $Members = if ($Role.members) { $role.members | ForEach-Object { " $($_.displayName) ($($_.userPrincipalName))" } } else { 'none' }
        [PSCustomObject]@{
            DisplayName = $Role.displayName
            Description = $Role.description
            Members     = $Members -join ','
        }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $GraphRequest
        })

}

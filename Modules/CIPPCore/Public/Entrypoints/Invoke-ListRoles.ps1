using namespace System.Net

Function Invoke-ListRoles {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Role.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $SelectList = 'id', 'displayName', 'userPrincipalName'

    [System.Collections.Generic.List[PSCustomObject]]$Roles = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/directoryRoles?`$expand=members" -tenantid $TenantFilter
    $GraphRequest = foreach ($Role in $Roles) {

        #[System.Collections.Generic.List[PSCustomObject]]$Members = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/directoryRoles/$($Role.id)/members?`$select=$($SelectList -join ',')" -tenantid $TenantFilter | Select-Object $SelectList
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

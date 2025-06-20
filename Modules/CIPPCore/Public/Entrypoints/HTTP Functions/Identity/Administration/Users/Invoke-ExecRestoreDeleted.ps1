using namespace System.Net

Function Invoke-ExecRestoreDeleted {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Directory.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $RequestID = $Request.Query.ID ?? $Request.Body.ID
    $UserPrincipalName = $Request.Body.userPrincipalName
    $DisplayName = $Request.Body.displayName

    try {
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/directory/deletedItems/$($RequestID)/restore" -tenantid $TenantFilter -type POST -body '{}' -Verbose
        $Result = "Successfully restored deleted item with ID: '$($RequestID)'"
        if ($UserPrincipalName) { $Result += " User Principal Name: '$($UserPrincipalName)'" }
        if ($DisplayName) { $Result += " Display Name: '$($DisplayName)'" }

        Write-LogMessage -headers $Headers -tenant $TenantFilter -API $APIName -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to restore deleted item with ID: '$($RequestID)'"
        if ($UserPrincipalName) { $Result += " User Principal Name: '$($UserPrincipalName)'" }
        if ($DisplayName) { $Result += " Display Name: '$($DisplayName)'" }
        $Result += " Error: $($ErrorMessage.NormalizedError)"

        Write-LogMessage -headers $Headers -tenant $TenantFilter -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })

}

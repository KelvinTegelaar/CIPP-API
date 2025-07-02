using namespace System.Net

function Invoke-ExecDisableUser {
    <#
    .SYNOPSIS
    Enable or disable a user account in Microsoft Entra ID (Azure AD)
    
    .DESCRIPTION
    Enables or disables a user account in Microsoft Entra ID (Azure AD) for a specified tenant, supporting both enable and disable operations with error handling and logging.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    
    .NOTES
    Group: Identity Management
    Summary: Exec Disable User
    Description: Enables or disables a user account in Microsoft Entra ID (Azure AD) for a specified tenant, supporting both enable and disable operations with error handling and logging.
    Tags: Identity,User,Enable,Disable,Azure AD,Entra ID
    Parameter: tenantFilter (string) [query/body] - Target tenant identifier
    Parameter: ID (string) [query/body] - User ID to enable or disable
    Parameter: Enable (bool) [query/body] - Whether to enable (true) or disable (false) the user
    Response: Returns a response object with the following properties:
    Response: - Results (string): Success or error message
    Response: On success: "User enabled/disabled successfully."
    Response: On error: Error message with HTTP 500 status
    Example: {
      "Results": "User enabled successfully."
    }
    Error: Returns error details if the operation fails to enable or disable the user.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $ID = $Request.Query.ID ?? $Request.Body.ID
    $Enable = $Request.Query.Enable ?? $Request.Body.Enable
    $Enable = [System.Convert]::ToBoolean($Enable)

    try {
        $Result = Set-CIPPSignInState -UserID $ID -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers -AccountEnabled $Enable
        if ($Result -like 'Could not disable*' -or $Result -like 'WARNING: User is AD Sync enabled*') { throw $Result }
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = "$Result" }
        })

}

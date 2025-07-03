using namespace System.Net

function Invoke-ExecClrImmId {
    <#
    .SYNOPSIS
    Clear the immutable ID for a user in Microsoft Entra ID (Azure AD)
    
    .DESCRIPTION
    Clears the immutable ID for a specified user in Microsoft Entra ID (Azure AD), which is useful for resolving synchronization issues or preparing for directory changes.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    
    .NOTES
    Group: Identity Management
    Summary: Exec Clear Immutable ID
    Description: Clears the immutable ID for a specified user in Microsoft Entra ID (Azure AD), which is useful for resolving synchronization issues or preparing for directory changes.
    Tags: Identity,User,Immutable ID,Azure AD,Entra ID
    Parameter: tenantFilter (string) [query/body] - Target tenant identifier
    Parameter: ID (string) [query/body] - User ID to clear immutable ID for
    Response: Returns a response object with the following properties:
    Response: - Results (string): Success or error message
    Response: On success: Success message indicating immutable ID was cleared
    Response: On error: Error message with HTTP 500 status
    Example: {
      "Results": "Successfully cleared immutable ID for user 12345678-1234-1234-1234-123456789012."
    }
    Error: Returns error details if the operation fails to clear the immutable ID.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev Debug

    # Interact with body parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $UserID = $Request.Query.ID ?? $Request.Body.ID

    try {
        $Result = Clear-CIPPImmutableID -UserID $UserID -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}

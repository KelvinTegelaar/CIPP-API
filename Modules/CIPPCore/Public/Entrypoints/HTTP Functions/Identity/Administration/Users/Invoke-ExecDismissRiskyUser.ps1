function Invoke-ExecDismissRiskyUser {
    <#
    .SYNOPSIS
    Dismiss user risk for a specified user in Microsoft Entra ID (Azure AD)
    
    .DESCRIPTION
    Dismisses user risk for a specified user in Microsoft Entra ID (Azure AD) by calling the Microsoft Graph riskyUsers/dismiss endpoint. Logs success or failure.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    
    .NOTES
    Group: Identity Management
    Summary: Exec Dismiss Risky User
    Description: Dismisses user risk for a specified user in Microsoft Entra ID (Azure AD) by calling the Microsoft Graph riskyUsers/dismiss endpoint. Logs success or failure.
    Tags: Identity,User,Risk,Dismiss,Azure AD,Entra ID
    Parameter: tenantFilter (string) [query/body] - Target tenant identifier
    Parameter: userId (string) [query/body] - User ID to dismiss risk for
    Parameter: userDisplayName (string) [query/body] - User display name for logging
    Response: Returns a response object with the following properties:
    Response: - Results (string): Success or error message
    Response: On success: "Successfully dismissed User Risk for user [userDisplayName]."
    Response: On error: Error message with HTTP 500 status
    Example: {
      "Results": "Successfully dismissed User Risk for user John Doe."
    }
    Error: Returns error details if the operation fails to dismiss user risk.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with the query or body of the request
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $SuspectUser = $Request.Query.userId ?? $Request.Body.userId
    $userDisplayName = $Request.Query.userDisplayName ?? $Request.Body.userDisplayName

    $GraphRequest = @{
        'uri'         = 'https://graph.microsoft.com/beta/riskyUsers/dismiss'
        'tenantid'    = $TenantFilter
        'type'        = 'POST'
        'contentType' = 'application/json; charset=utf-8'
        'body'        = @{
            'userIds' = @($SuspectUser)
        } | ConvertTo-Json
    }

    try {
        $GraphResults = New-GraphPostRequest @GraphRequest
        $Result = "Successfully dismissed User Risk for user $userDisplayName. $GraphResults"
        Write-LogMessage -API $APIName -tenant $TenantFilter -message $Result -sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to dismiss user risk for $userDisplayName. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API $APIName -tenant $TenantFilter -message $Result -sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = $Result }
        })
}

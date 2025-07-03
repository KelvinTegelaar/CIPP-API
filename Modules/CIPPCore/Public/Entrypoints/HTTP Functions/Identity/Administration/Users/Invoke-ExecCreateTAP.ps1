using namespace System.Net

function Invoke-ExecCreateTAP {
    <#
    .SYNOPSIS
    Create a Temporary Access Pass (TAP) for a user in Microsoft Entra ID (Azure AD)
    
    .DESCRIPTION
    Creates a Temporary Access Pass (TAP) for a specified user in Microsoft Entra ID (Azure AD), with options for lifetime, single-use, and start time. Returns TAP details and user ID.
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    
    .NOTES
    Group: Identity Management
    Summary: Exec Create TAP
    Description: Creates a Temporary Access Pass (TAP) for a specified user in Microsoft Entra ID (Azure AD), with options for lifetime, single-use, and start time. Returns TAP details and user ID for onboarding or recovery scenarios.
    Tags: Identity,Temporary Access Pass,TAP,Azure AD,Entra ID
    Parameter: tenantFilter (string) [query/body] - Target tenant identifier
    Parameter: ID (string) [query/body] - User ID to create TAP for
    Parameter: lifetimeInMinutes (int) [query/body] - Lifetime of the TAP in minutes
    Parameter: isUsableOnce (bool) [query/body] - Whether the TAP is single-use
    Parameter: startDateTime (string) [query/body] - Start time for the TAP (ISO 8601 format)
    Response: Returns a response object with the following properties:
    Response: - Results (array): Array containing TAP details and user ID
    Response: On success: TAP object and user ID with HTTP 200 status
    Response: On error: Error message with HTTP 500 status
    Example: {
      "Results": [
        {
          "temporaryAccessPass": "123456",
          "lifetimeInMinutes": 60,
          "isUsableOnce": true,
          "startDateTime": "2024-01-15T10:30:00Z"
        },
        {
          "resultText": "User ID: 12345678-1234-1234-1234-123456789012",
          "copyField": "12345678-1234-1234-1234-123456789012",
          "state": "success"
        }
      ]
    }
    Error: Returns error details if the operation fails to create the TAP.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $UserID = $Request.Query.ID ?? $Request.Body.ID
    $LifetimeInMinutes = $Request.Query.lifetimeInMinutes ?? $Request.Body.lifetimeInMinutes
    $IsUsableOnce = $Request.Query.isUsableOnce ?? $Request.Body.isUsableOnce
    $StartDateTime = $Request.Query.startDateTime ?? $Request.Body.startDateTime

    try {
        # Create parameter hashtable for splatting
        $TAPParams = @{
            UserID            = $UserID
            TenantFilter      = $TenantFilter
            APIName           = $APIName
            Headers           = $Headers
            LifetimeInMinutes = $LifetimeInMinutes
            IsUsableOnce      = $IsUsableOnce
            StartDateTime     = $StartDateTime
        }

        $TAPResult = New-CIPPTAP @TAPParams

        # Create results array with both TAP and UserID as separate items
        $Results = @(
            $TAPResult,
            @{
                resultText = "User ID: $UserID"
                copyField  = $UserID
                state      = 'success'
            }
        )

        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $Results = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Results }
        })

}

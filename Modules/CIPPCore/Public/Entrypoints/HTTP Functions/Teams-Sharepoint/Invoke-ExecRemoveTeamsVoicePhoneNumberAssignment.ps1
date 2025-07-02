using namespace System.Net

function Invoke-ExecRemoveTeamsVoicePhoneNumberAssignment {
    <#
    .SYNOPSIS
    Execute Teams voice phone number removal
    
    .DESCRIPTION
    Removes phone number assignments from Teams users using Teams PowerShell cmdlets
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Teams.Voice.ReadWrite
        
    .NOTES
    Group: Teams & SharePoint
    Summary: Exec Remove Teams Voice Phone Number Assignment
    Description: Removes phone number assignments from Teams users using Teams PowerShell cmdlets with support for different phone number types
    Tags: Teams,Voice,Phone Numbers,Removal
    Parameter: tenantFilter (string) [body] - Target tenant identifier
    Parameter: AssignedTo (string) [body] - User identity to remove phone number from
    Parameter: PhoneNumber (string) [body] - Phone number to remove
    Parameter: PhoneNumberType (string) [body] - Type of phone number (User, Service, etc.)
    Response: Returns an object with the following properties:
    Response: - Results (string): Success or error message
    Response: On success: Success message with HTTP 200 status
    Response: On error: Error message with HTTP 500 status
    Example: {
      "Results": "Successfully unassigned +1234567890 from user@contoso.com"
    }
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter
    $AssignedTo = $Request.Body.AssignedTo
    $PhoneNumber = $Request.Body.PhoneNumber
    $PhoneNumberType = $Request.Body.PhoneNumberType

    try {
        $null = New-TeamsRequest -TenantFilter $TenantFilter -Cmdlet 'Remove-CsPhoneNumberAssignment' -CmdParams @{Identity = $AssignedTo; PhoneNumber = $PhoneNumber; PhoneNumberType = $PhoneNumberType; ErrorAction = 'Stop' }
        $Result = "Successfully unassigned $PhoneNumber from $AssignedTo"
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to unassign $PhoneNumber from $AssignedTo. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}

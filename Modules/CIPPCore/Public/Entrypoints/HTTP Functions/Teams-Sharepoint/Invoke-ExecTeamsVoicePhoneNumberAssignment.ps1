using namespace System.Net

function Invoke-ExecTeamsVoicePhoneNumberAssignment {
    <#
    .SYNOPSIS
    Execute Teams voice phone number assignment
    
    .DESCRIPTION
    Assigns phone numbers to Teams users or emergency locations using Teams PowerShell cmdlets
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Teams.Voice.ReadWrite
        
    .NOTES
    Group: Teams & SharePoint
    Summary: Exec Teams Voice Phone Number Assignment
    Description: Assigns phone numbers to Teams users or emergency locations using Teams PowerShell cmdlets with support for different phone number types and location assignments
    Tags: Teams,Voice,Phone Numbers,Assignment
    Parameter: input.value (string) [body] - User identity or location ID for assignment
    Parameter: TenantFilter (string) [body] - Target tenant identifier
    Parameter: PhoneNumber (string) [body] - Phone number to assign
    Parameter: PhoneNumberType (string) [body] - Type of phone number (User, Service, etc.)
    Parameter: locationOnly (boolean) [body] - Whether to assign to emergency location only
    Response: Returns an object with the following properties:
    Response: - Results (string): Success or error message
    Response: On success: Success message with HTTP 200 status
    Response: On error: Error message with HTTP 403 status
    Example: {
      "Results": "Successfully assigned +1234567890 to user@contoso.com"
    }
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -Headers $Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $Identity = $Request.Body.input.value

    $tenantFilter = $Request.Body.TenantFilter
    try {
        if ($Request.Body.locationOnly) {
            $null = New-TeamsRequest -TenantFilter $TenantFilter -Cmdlet 'Set-CsPhoneNumberAssignment' -CmdParams @{LocationId = $Identity; PhoneNumber = $Request.Body.PhoneNumber; ErrorAction = 'stop' }
            $Results = [pscustomobject]@{'Results' = "Successfully assigned emergency location to $($Request.Body.PhoneNumber)" }
        }
        else {
            $null = New-TeamsRequest -TenantFilter $TenantFilter -Cmdlet 'Set-CsPhoneNumberAssignment' -CmdParams @{Identity = $Identity; PhoneNumber = $Request.Body.PhoneNumber; PhoneNumberType = $Request.Body.PhoneNumberType; ErrorAction = 'stop' }
            $Results = [pscustomobject]@{'Results' = "Successfully assigned $($Request.Body.PhoneNumber) to $($Identity)" }
        }
        Write-LogMessage -Headers $Headers -API $APINAME -tenant $($TenantFilter) -message $($Results.Results) -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = [pscustomobject]@{'Results' = $ErrorMessage.NormalizedError }
        Write-LogMessage -Headers $Headers -API $APINAME -tenant $($TenantFilter) -message $($Results.Results) -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}

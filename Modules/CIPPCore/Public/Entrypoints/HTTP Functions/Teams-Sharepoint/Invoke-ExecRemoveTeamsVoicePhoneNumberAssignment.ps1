Function Invoke-ExecRemoveTeamsVoicePhoneNumberAssignment {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Teams.Voice.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


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
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to unassign $PhoneNumber from $AssignedTo. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}

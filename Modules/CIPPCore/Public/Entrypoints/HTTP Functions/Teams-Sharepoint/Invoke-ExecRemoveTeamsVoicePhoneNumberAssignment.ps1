using namespace System.Net

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
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $tenantFilter = $Request.Body.TenantFilter
    try {
        $null = New-TeamsRequest -TenantFilter $TenantFilter -Cmdlet 'Remove-CsPhoneNumberAssignment' -CmdParams @{Identity = $Request.Body.AssignedTo; PhoneNumber = $Request.Body.PhoneNumber; PhoneNumberType = $Request.Body.PhoneNumberType; ErrorAction = 'stop'}
        $Results = [pscustomobject]@{'Results' = "Successfully unassigned $($Request.Body.PhoneNumber) from $($Request.Body.AssignedTo)"}
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $($TenantFilter) -message $($Results.Results) -Sev 'Info'
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $Results = [pscustomobject]@{'Results' = $ErrorMessage}
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $($TenantFilter) -message $($Results.Results) -Sev 'Error'
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })
}

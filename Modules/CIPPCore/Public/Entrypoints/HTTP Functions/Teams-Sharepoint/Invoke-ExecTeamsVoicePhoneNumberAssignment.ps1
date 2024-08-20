using namespace System.Net

Function Invoke-ExecTeamsVoicePhoneNumberAssignment {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Teams.Voice.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $tenantFilter = $Request.Body.TenantFilter
    try {
        if ($Request.Body.locationOnly) {
            $null = New-TeamsRequest -TenantFilter $TenantFilter -Cmdlet 'Set-CsPhoneNumberAssignment' -CmdParams @{LocationId = $Request.Body.input; PhoneNumber = $Request.Body.PhoneNumber; ErrorAction = 'stop'}
            $Results = [pscustomobject]@{'Results' = "Successfully assigned emergency location to $($Request.Body.PhoneNumber)"}
        } else {
            $null = New-TeamsRequest -TenantFilter $TenantFilter -Cmdlet 'Set-CsPhoneNumberAssignment' -CmdParams @{Identity = $Request.Body.input; PhoneNumber = $Request.Body.PhoneNumber; PhoneNumberType = $Request.Body.PhoneNumberType; ErrorAction = 'stop'}
            $Results = [pscustomobject]@{'Results' = "Successfully assigned $($Request.Body.PhoneNumber) to $($Request.Body.input)"}
        }
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($TenantFilter) -message $($Results.Results) -Sev 'Info'
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $Results = [pscustomobject]@{'Results' = $ErrorMessage}
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($TenantFilter) -message $($Results.Results) -Sev 'Error'
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })
}

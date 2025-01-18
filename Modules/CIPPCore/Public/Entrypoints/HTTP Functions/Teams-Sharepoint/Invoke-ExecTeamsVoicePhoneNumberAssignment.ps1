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
    $ExecutingUser = $Request.headers.'x-ms-client-principal'
    Write-LogMessage -user $ExecutingUser -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $Identity = $Request.Body.input.value

    $tenantFilter = $Request.Body.TenantFilter
    try {
        if ($Request.Body.locationOnly) {
            $null = New-TeamsRequest -TenantFilter $TenantFilter -Cmdlet 'Set-CsPhoneNumberAssignment' -CmdParams @{LocationId = $Identity; PhoneNumber = $Request.Body.PhoneNumber; ErrorAction = 'stop' }
            $Results = [pscustomobject]@{'Results' = "Successfully assigned emergency location to $($Request.Body.PhoneNumber)" }
        } else {
            $null = New-TeamsRequest -TenantFilter $TenantFilter -Cmdlet 'Set-CsPhoneNumberAssignment' -CmdParams @{Identity = $Identity; PhoneNumber = $Request.Body.PhoneNumber; PhoneNumberType = $Request.Body.PhoneNumberType; ErrorAction = 'stop' }
            $Results = [pscustomobject]@{'Results' = "Successfully assigned $($Request.Body.PhoneNumber) to $($Identity)" }
        }
        Write-LogMessage -user $ExecutingUser -API $APINAME -tenant $($TenantFilter) -message $($Results.Results) -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = [pscustomobject]@{'Results' = $ErrorMessage.NormalizedError }
        Write-LogMessage -user $ExecutingUser -API $APINAME -tenant $($TenantFilter) -message $($Results.Results) -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}

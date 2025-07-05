using namespace System.Net

function Invoke-ExecTeamsVoicePhoneNumberAssignment {
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
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $TenantFilter = $Request.Body.TenantFilter
    $Identity = $Request.Body.input.value
    $PhoneNumber = $Request.Body.PhoneNumber
    $PhoneNumberType = $Request.Body.PhoneNumberType
    try {
        if ($Request.Body.locationOnly) {
            $null = New-TeamsRequest -TenantFilter $TenantFilter -Cmdlet 'Set-CsPhoneNumberAssignment' -CmdParams @{LocationId = $Identity; PhoneNumber = $PhoneNumber; ErrorAction = 'Stop' }
            $Results = "Successfully assigned emergency location to $($PhoneNumber)"
        } else {
            $null = New-TeamsRequest -TenantFilter $TenantFilter -Cmdlet 'Set-CsPhoneNumberAssignment' -CmdParams @{Identity = $Identity; PhoneNumber = $PhoneNumber; PhoneNumberType = $PhoneNumberType; ErrorAction = 'Stop' }
            $Results = "Successfully assigned $($PhoneNumber) to $($Identity)"
        }
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = $ErrorMessage.NormalizedError
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    return @{
        StatusCode = $StatusCode
        Body       = @{ Results = $Results }
    }
}

using namespace System.Net

Function Invoke-ExecSetOoO {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    try {
        $APIName = $Request.Params.CIPPEndpoint
        $Headers = $Request.Headers
        Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


        $Username = $Request.Body.userId
        $TenantFilter = $Request.Body.tenantFilter
        $State = $Request.Body.AutoReplyState.value

        $SplatParams = @{
            userid       = $Username
            tenantFilter = $TenantFilter
            APIName      = $APIName
            Headers      = $Headers
            State        = $State
        }

        # User action uses input, edit exchange uses InternalMessage and ExternalMessage
        # User action disable OoO doesn't send any input
        if ($Request.Body.input) {
            $SplatParams.InternalMessage = $Request.Body.input
            $SplatParams.ExternalMessage = $Request.Body.input
        } else {
            $InternalMessage = $Request.Body.InternalMessage
            $ExternalMessage = $Request.Body.ExternalMessage

            # Only add the internal and external message if they are not empty/null. Done to be able to set the OOO to disabled, while keeping the existing messages intact.
            # This works because the frontend always sends some HTML even if the fields are empty.
            if (-not [string]::IsNullOrWhiteSpace($InternalMessage)) {
                $SplatParams.InternalMessage = $InternalMessage
            }
            if (-not [string]::IsNullOrWhiteSpace($ExternalMessage)) {
                $SplatParams.ExternalMessage = $ExternalMessage
            }
        }


        # If the state is scheduled, add the start and end times to the splat params
        if ($State -eq 'Scheduled') {
            # If starttime and endtime are a number, they are unix timestamps and need to be converted to datetime, otherwise just use them.
            $StartTime = $Request.Body.StartTime -match '^\d+$' ? [DateTimeOffset]::FromUnixTimeSeconds([int]$Request.Body.StartTime).DateTime : $Request.Body.StartTime
            $EndTime = $Request.Body.EndTime -match '^\d+$' ? [DateTimeOffset]::FromUnixTimeSeconds([int]$Request.Body.EndTime).DateTime : $Request.Body.EndTime
            $SplatParams.StartTime = $StartTime
            $SplatParams.EndTime = $EndTime
        }

        $Results = Set-CIPPOutOfOffice @SplatParams
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Could not set Out of Office for user: $($Username). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $($Results) }
        })

}

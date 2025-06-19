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

        if ($Request.Body.input) {
            $InternalMessage = $Request.Body.input
            $ExternalMessage = $Request.Body.input
        } else {
            $InternalMessage = $Request.Body.InternalMessage
            $ExternalMessage = $Request.Body.ExternalMessage
        }
        #if starttime and endtime are a number, they are unix timestamps and need to be converted to datetime, otherwise just use them.
        $StartTime = $Request.Body.StartTime -match '^\d+$' ? [DateTimeOffset]::FromUnixTimeSeconds([int]$Request.Body.StartTime).DateTime : $Request.Body.StartTime
        $EndTime = $Request.Body.EndTime -match '^\d+$' ? [DateTimeOffset]::FromUnixTimeSeconds([int]$Request.Body.EndTime).DateTime : $Request.Body.EndTime


        $SplatParams = @{
            userid          = $Username
            tenantFilter    = $TenantFilter
            APIName         = $APIName
            Headers         = $Headers
            InternalMessage = $InternalMessage
            ExternalMessage = $ExternalMessage
            State           = $State
        }

        # If the state is scheduled, add the start and end times to the splat params
        if ($State -eq 'Scheduled') {
            $SplatParams.StartTime = $StartTime
            $SplatParams.EndTime = $EndTime
        }

        $Results = Set-CIPPOutOfOffice @SplatParams


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

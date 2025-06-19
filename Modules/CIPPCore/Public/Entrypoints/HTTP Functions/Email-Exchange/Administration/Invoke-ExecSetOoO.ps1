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

        if ($Request.Body.input) {
            $InternalMessage = $Request.Body.input
            $ExternalMessage = $Request.Body.input
        } else {
            $InternalMessage = $Request.Body.InternalMessage
            $ExternalMessage = $Request.Body.ExternalMessage
        }
        #if starttime and endtime are a number, they are unix timestamps and need to be converted to datetime, otherwise just use them.
        $StartTime = if ($Request.Body.StartTime -match '^\d+$') { [DateTimeOffset]::FromUnixTimeSeconds([int]$Request.Body.StartTime).DateTime } else { $Request.Body.StartTime }
        $EndTime = if ($Request.Body.EndTime -match '^\d+$') { [DateTimeOffset]::FromUnixTimeSeconds([int]$Request.Body.EndTime).DateTime } else { $Request.Body.EndTime }


        if ($Request.Body.AutoReplyState.value -ne 'Scheduled') {
            $Results = Set-CIPPOutOfOffice -userid $Username -tenantFilter $TenantFilter -APIName $APIName -Headers $Headers -InternalMessage $InternalMessage -ExternalMessage $ExternalMessage -State $Request.Body.AutoReplyState.value
        } else {
            $Results = Set-CIPPOutOfOffice -userid $Username -tenantFilter $TenantFilter -APIName $APIName -Headers $Headers -InternalMessage $InternalMessage -ExternalMessage $ExternalMessage -StartTime $StartTime -EndTime $EndTime -State $Request.Body.AutoReplyState.value
        }


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

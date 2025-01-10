using namespace System.Net

Function Invoke-ExecSetOoO {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    try {
        $APIName = $TriggerMetadata.FunctionName
        Write-LogMessage -user $request.headers.'X-MS-CLIENT-PRINCIPAL' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
        $Username = $request.body.userId
        $Tenantfilter = $request.body.tenantfilter
        if ($Request.body.input) {
            $InternalMessage = $Request.body.input
            $ExternalMessage = $Request.body.input
        } else {
            $InternalMessage = $Request.body.InternalMessage
            $ExternalMessage = $Request.body.ExternalMessage
        }
        #if starttime and endtime are a number, they are unix timestamps and need to be converted to datetime, otherwise just use them.
        $StartTime = if ($Request.body.StartTime -match '^\d+$') { [DateTimeOffset]::FromUnixTimeSeconds([int]$Request.body.StartTime).DateTime } else { $Request.body.StartTime }
        $EndTime = if ($Request.body.EndTime -match '^\d+$') { [DateTimeOffset]::FromUnixTimeSeconds([int]$Request.body.EndTime).DateTime } else { $Request.body.EndTime }

        $Results = try {
            if ($Request.Body.AutoReplyState.value -ne 'Scheduled') {
                Set-CIPPOutOfOffice -userid $Username -tenantFilter $TenantFilter -APIName $APINAME -ExecutingUser $request.headers.'X-MS-CLIENT-PRINCIPAL' -InternalMessage $InternalMessage -ExternalMessage $ExternalMessage -State $Request.Body.AutoReplyState.value
            } else {
                Set-CIPPOutOfOffice -userid $Username -tenantFilter $TenantFilter -APIName $APINAME -ExecutingUser $request.headers.'X-MS-CLIENT-PRINCIPAL' -InternalMessage $InternalMessage -ExternalMessage $ExternalMessage -StartTime $StartTime -EndTime $EndTime -State $Request.Body.AutoReplyState.value
            }
        } catch {
            "Could not add out of office message for $($username). Error: $($_.Exception.Message)"
        }

        $body = [pscustomobject]@{'Results' = $($results) }
    } catch {
        $body = [pscustomobject]@{'Results' = "Could not set Out of Office user: $($_.Exception.message)" }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}

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
        Write-LogMessage -headers $Request.Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'
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

        $Results = try {
            if ($Request.Body.AutoReplyState.value -ne 'Scheduled') {
                Set-CIPPOutOfOffice -userid $Username -tenantFilter $TenantFilter -APIName $APIName -Headers $Request.Headers -InternalMessage $InternalMessage -ExternalMessage $ExternalMessage -State $Request.Body.AutoReplyState.value
            } else {
                Set-CIPPOutOfOffice -userid $Username -tenantFilter $TenantFilter -APIName $APIName -Headers $Request.Headers -InternalMessage $InternalMessage -ExternalMessage $ExternalMessage -StartTime $StartTime -EndTime $EndTime -State $Request.Body.AutoReplyState.value
            }
        } catch {
            "Could not add out of office message for $($Username). Error: $($_.Exception.Message)"
        }

        $Body = [PSCustomObject]@{'Results' = $($Results) }
    } catch {
        $Body = [PSCustomObject]@{'Results' = "Could not set Out of Office user: $($_.Exception.Message)" }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}

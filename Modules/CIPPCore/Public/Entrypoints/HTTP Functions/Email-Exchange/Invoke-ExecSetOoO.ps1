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
        $APIName = $TriggerMetadata.FunctionName
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
        $Username = $request.body.user
        $Tenantfilter = $request.body.tenantfilter
        if ($Request.body.input) {
            $InternalMessage = $Request.body.input
            $ExternalMessage = $Request.body.input
        } else {
            $InternalMessage = $Request.body.InternalMessage
            $ExternalMessage = $Request.body.ExternalMessage
        }
        $StartTime = $Request.body.StartTime
        $EndTime = $Request.body.EndTime

        $OutOfOffice = @{
            userid          = $Request.body.user
            InternalMessage = $InternalMessage
            ExternalMessage = $ExternalMessage
            TenantFilter    = $TenantFilter
            State           = $Request.Body.AutoReplyState
            APIName         = $APINAME
            ExecutingUser   = $request.headers.'x-ms-client-principal'
            StartTime       = $StartTime
            EndTime         = $EndTime
        }
        Write-Host ($OutOfOffice | ConvertTo-Json -Depth 10)

        $Results = try {
            Set-CIPPOutOfOffice @OutOfOffice
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

using namespace System.Net

Function Invoke-ExecDisableEmailForward {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    try {
        $APIName = $TriggerMetadata.FunctionName
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
        $Username = $request.body.user
        $Tenantfilter = $request.body.tenantfilter
        $Results = try {
            Set-CIPPForwarding -userid $Request.body.user -tenantFilter $TenantFilter -APIName $APINAME -ExecutingUser $request.headers.'x-ms-client-principal' -Forward $null -keepCopy $false -ForwardingSMTPAddress $null -Disable $true
        } catch {
            "Could not disable forwarding message for $($username). Error: $($_.Exception.Message)"
        }

        $body = [pscustomobject]@{'Results' = @($results) }
    } catch {
        $body = [pscustomobject]@{'Results' = @("Could not disable forwarding user: $($_.Exception.message)") }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}

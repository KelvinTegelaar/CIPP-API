using namespace System.Net

Function Invoke-ExecSetSecurityAlert {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Security.Alert.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $tenantfilter = $Request.Query.TenantFilter
    $AlertFilter = $Request.Query.GUID
    $Status = $Request.Query.Status
    $AssignBody = '{"status":"' + $Status + '","vendorInformation":{"provider":"' + $Request.query.provider + '","vendor":"' + $Request.query.vendor + '"}}'
    try {
        $GraphRequest = New-Graphpostrequest -uri "https://graph.microsoft.com/beta/security/alerts/$AlertFilter" -type PATCH -tenantid $TenantFilter -body $Assignbody
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $($tenantfilter) -message "Set alert $AlertFilter to status $Status" -Sev 'Info'
        $body = [pscustomobject]@{'Results' = "Set status for alert to $Status" }

    } catch {
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $($tenantfilter) -message "Failed to update alert $($AlertFilter): $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Failed to change status: $($_.Exception.Message)" }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}

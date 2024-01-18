using namespace System.Net

Function Invoke-ExecSyncAPDevices {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $tenantfilter = $Request.Query.TenantFilter
    try {
        New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotSettings/sync' -tenantid $TenantFilter
        $Results = "Successfully Started Sync for $($TenantFilter)"
    } catch {
        $Results = "Failed to start sync for $tenantfilter. Did you try syncing in the last 10 minutes?"
    }

    $Results = [pscustomobject]@{'Results' = "$results" }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })

}

Function Invoke-ExecSyncAPDevices {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Autopilot.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter ?? $Request.Query.tenantFilter
    Write-LogMessage -Headers $Headers -API $APINAME -message 'Accessed this API' -Sev Debug

    try {
        $null = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotSettings/sync' -tenantid $TenantFilter
        $Results = "Successfully Started Sync for $($TenantFilter)"
        Write-LogMessage -Headers $Headers -API $APINAME -tenant $TenantFilter -message 'Successfully started Autopilot sync' -Sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to start sync for $TenantFilter. Did you try syncing in the last 10 minutes?"
        Write-LogMessage -Headers $Headers -API $APINAME -tenant $TenantFilter -message 'Failed to start Autopilot sync. Did you try syncing in the last 10 minutes?' -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    $Results = [pscustomobject]@{'Results' = "$Results" }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })

}

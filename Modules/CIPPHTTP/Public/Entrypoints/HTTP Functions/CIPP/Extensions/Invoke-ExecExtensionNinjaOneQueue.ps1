function Invoke-ExecExtensionNinjaOneQueue {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Extension.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $NinjaAction = $QueueItem.NinjaAction

    try {
        switch ($NinjaAction) {
            'StartAutoMapping' {
                Invoke-NinjaOneOrgMapping
                Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message 'NinjaOne StartAutoMapping completed' -Sev 'Info'
            }
            'AutoMapTenant' {
                Invoke-NinjaOneOrgMappingTenant -QueueItem $QueueItem
                Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message 'NinjaOne AutoMapTenant completed' -Sev 'Info'
            }
            'SyncTenant' {
                Invoke-NinjaOneTenantSync -QueueItem $QueueItem
                Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message 'NinjaOne SyncTenant completed' -Sev 'Info'
            }
            default {
                Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "Unknown NinjaOne action: $NinjaAction" -Sev 'Error'
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message "NinjaOne action '$NinjaAction' failed: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
    }

    $Body = [PSCustomObject]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = 'Success'
    }

    return [HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    }
}

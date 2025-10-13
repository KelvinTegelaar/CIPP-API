function Invoke-ExecExtensionNinjaOneQueue {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Extension.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    switch ($QueueItem.NinjaAction) {
        'StartAutoMapping' { Invoke-NinjaOneOrgMapping }
        'AutoMapTenant' { Invoke-NinjaOneOrgMappingTenant -QueueItem $QueueItem }
        'SyncTenant' { Invoke-NinjaOneTenantSync -QueueItem $QueueItem }
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

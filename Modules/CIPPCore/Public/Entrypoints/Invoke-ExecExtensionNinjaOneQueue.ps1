using namespace System.Net

Function Invoke-ExecExtensionNinjaOneQueue {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Extension.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)



    Switch ($QueueItem.NinjaAction) {
        'StartAutoMapping' { Invoke-NinjaOneOrgMapping }
        'AutoMapTenant' { Invoke-NinjaOneOrgMappingTenant -QueueItem $QueueItem }
        'SyncTenant' { Invoke-NinjaOneTenantSync -QueueItem $QueueItem }
    }

    $Body = [PSCustomObject]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = 'Success'
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $Body
    })
}

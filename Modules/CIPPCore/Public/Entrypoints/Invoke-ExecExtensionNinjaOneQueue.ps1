using namespace System.Net

Function Invoke-ExecExtensionNinjaOneQueue {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

        

    Switch ($QueueItem.NinjaAction) {
        'StartAutoMapping' { Invoke-NinjaOneOrgMapping }
        'AutoMapTenant' { Invoke-NinjaOneOrgMappingTenant -QueueItem $QueueItem } 
        'SyncTenant' { Invoke-NinjaOneTenantSync -QueueItem $QueueItem }
    }

}

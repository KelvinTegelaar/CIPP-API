using namespace System.Net

Function Invoke-ExecExtensionNinjaOneQueue {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Extension.NinjaOne.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)



    Switch ($QueueItem.NinjaAction) {
        'StartAutoMapping' { Invoke-NinjaOneOrgMapping }
        'AutoMapTenant' { Invoke-NinjaOneOrgMappingTenant -QueueItem $QueueItem }
        'SyncTenant' { Invoke-NinjaOneTenantSync -QueueItem $QueueItem }
    }

}

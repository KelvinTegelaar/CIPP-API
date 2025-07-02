using namespace System.Net

function Invoke-ExecExtensionNinjaOneQueue {
    <#
    .SYNOPSIS
    Execute NinjaOne extension queue operations
    
    .DESCRIPTION
    Processes NinjaOne extension queue items for organization mapping, tenant synchronization, and auto-mapping operations
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Extension.ReadWrite
        
    .NOTES
    Group: Extensions
    Summary: Exec Extension NinjaOne Queue
    Description: Processes NinjaOne extension queue items for various operations including organization mapping, tenant auto-mapping, and tenant synchronization
    Tags: Extensions,NinjaOne,Queue,Integration
    Parameter: QueueItem (object) - Queue item containing NinjaOne action and parameters
    Parameter: QueueItem.NinjaAction (string) - Action to perform: StartAutoMapping, AutoMapTenant, or SyncTenant
    Response: Returns a response object with the following properties:
    Response: - StatusCode (number): HTTP status code (200 for success)
    Response: - Body (string): Success message
    Response: Actions performed based on NinjaAction:
    Response: - StartAutoMapping: Initiates organization mapping process
    Response: - AutoMapTenant: Performs auto-mapping for a specific tenant
    Response: - SyncTenant: Synchronizes data for a specific tenant
    Example: {
      "StatusCode": 200,
      "Body": "Success"
    }
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    switch ($QueueItem.NinjaAction) {
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

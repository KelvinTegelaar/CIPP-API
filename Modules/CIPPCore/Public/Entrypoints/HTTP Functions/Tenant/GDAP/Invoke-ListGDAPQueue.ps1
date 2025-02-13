using namespace System.Net

Function Invoke-ListGDAPQueue {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Relationship.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    $Table = Get-CIPPTable -TableName 'GDAPMigration'
    $QueuedApps = Get-CIPPAzDataTableEntity @Table

    $CurrentStandards = foreach ($QueueFile in $QueuedApps) {
        [PSCustomObject]@{
            Tenant  = $QueueFile.tenant
            Status  = $QueueFile.status
            StartAt = $QueueFile.startAt
        }
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($CurrentStandards)
        })

}

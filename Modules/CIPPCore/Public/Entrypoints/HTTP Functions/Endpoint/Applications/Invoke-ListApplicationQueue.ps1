using namespace System.Net

Function Invoke-ListApplicationQueue {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Application.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    Write-LogMessage -headers $Request.Headers -API $APINAME -message 'Accessed this API' -Sev 'Debug'


    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    $Table = Get-CippTable -tablename 'apps'
    $QueuedApps = (Get-CIPPAzDataTableEntity @Table)

    $CurrentApps = foreach ($QueueFile in $QueuedApps) {
        Write-Host $QueueFile
        $ApplicationFile = $QueueFile.JSON | ConvertFrom-Json -Depth 10
        [PSCustomObject]@{
            tenantName      = $ApplicationFile.tenant
            applicationName = $ApplicationFile.Applicationname
            cmdLine         = $ApplicationFile.IntuneBody.installCommandLine
            assignTo        = $ApplicationFile.assignTo
            id              = $($QueueFile.RowKey)
            status          = $($QueueFile.status)
        }
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($CurrentApps)
        })

}

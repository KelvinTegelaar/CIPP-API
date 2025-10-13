Function Invoke-ListApplicationQueue {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Application.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Table = Get-CippTable -tablename 'apps'
    $QueuedApps = (Get-CIPPAzDataTableEntity @Table)

    $CurrentApps = foreach ($QueueFile in $QueuedApps) {
        Write-Host $QueueFile
        $ApplicationFile = $QueueFile.JSON | ConvertFrom-Json -Depth 10
        [PSCustomObject]@{
            tenantName      = $ApplicationFile.tenant
            applicationName = $ApplicationFile.applicationName
            cmdLine         = $ApplicationFile.IntuneBody.installCommandLine
            assignTo        = $ApplicationFile.assignTo
            id              = $($QueueFile.RowKey)
            status          = $($QueueFile.status)
        }
    }


    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($CurrentApps)
        })

}

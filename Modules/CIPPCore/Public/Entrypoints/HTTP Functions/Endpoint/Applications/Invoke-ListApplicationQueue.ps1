using namespace System.Net

function Invoke-ListApplicationQueue {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Application.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


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


    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @($CurrentApps)
    }
}

using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME  -message "Accessed this API" -Sev "Debug"


# Write to the Azure Functions log stream.
Write-Host "PowerShell HTTP trigger function processed a request."
$Table = Get-CippTable -tablename 'apps'
$QueuedApps = (Get-CIPPAzDataTableEntity @Table)

$CurrentApps = foreach ($QueueFile in $QueuedApps) {
    Write-Host $QueueFile
    $ApplicationFile = $QueueFile.JSON | ConvertFrom-Json -depth 10
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

using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'


# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'
$Table = Get-CIPPTable -TableName 'GDAPMigration' 
$QueuedApps = Get-AzDataTableEntity @Table

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

using namespace System.Net

# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

# Write to the Azure Functions log stream.
Write-Host 'PowerShell HTTP trigger function processed a request.'

$Table = Get-CippTable -TableName 'MaintenanceScripts'

if (![string]::IsNullOrEmpty($Request.Query.Guid)) {
    $Filter = "PartitionKey eq 'Maintenance' and RowKey eq '{0}'" -f $Request.Query.Guid
    $ScriptRow = Get-CIPPAzDataTableEntity @Table -Filter $Filter
    if ($ScriptRow) {
        if ($ScriptRow.Timestamp.DateTime -lt (Get-Date).AddMinutes(-5)) {
            $Body = 'Write-Host "Link expired"'
        }
        else {
            $Body = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($ScriptRow.ScriptContent))
        }
        Remove-AzDataTableEntity @Table -Entity $ScriptRow
    }
    else {
        $Body = 'Write-Host "Invalid Script ID"'
    }
}
else {
    $Body = 'Write-Host "Script ID is required, generate a link from the Maintenance page"'
}

# Associate values to output bindings by calling 'Push-OutputBinding'.
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })

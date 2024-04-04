function Invoke-ListCippQueue {
    # Input bindings are passed in via param block.
    param($Request = $null, $TriggerMetadata)

    if ($Request) {
        $APIName = $TriggerMetadata.FunctionName
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

        # Write to the Azure Functions log stream.
        Write-Host 'PowerShell HTTP trigger function processed a request.'
    }

    $CippQueue = Get-CippTable -TableName 'CippQueue'
    $CippQueueData = Get-CIPPAzDataTableEntity @CippQueue | Where-Object { ($_.Timestamp.DateTime) -ge (Get-Date).ToUniversalTime().AddHours(-1) } | Sort-Object -Property Timestamp -Descending
    if ($request) {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @($CippQueueData)
            })
    } else {
        return $CippQueueData
    }
}
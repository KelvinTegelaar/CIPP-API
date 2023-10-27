using namespace System.Net
# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)


$body = if ($request.query.GUID) {
    $Table = Get-CippTable -tablename 'cachebec'
    $Filter = "PartitionKey eq 'bec' and RowKey eq '$($request.query.GUID)'" 
    $JSONOutput = Get-CIPPAzDataTableEntity @Table -Filter $Filter
    if (!$JSONOutput) {
        @{ Waiting = $true }
    }
    else {
        $JSONOutput.Results
    }
}
else {
    $OrchRequest = [PSCustomObject]@{
        TenantFilter = $request.query.tenantfilter
        UserID       = $request.query.userid
    }
    $InstanceId = Start-NewOrchestration -FunctionName 'Durable_BECRun' -InputObject $OrchRequest
    @{ GUID = $request.query.userid }
}


Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
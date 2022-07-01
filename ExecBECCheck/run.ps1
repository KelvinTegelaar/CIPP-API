using namespace System.Net
# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

if ($request.query.GUID) {
    $JSONOutput = Get-Content "Cache_BECCheck\$($Request.Query.GUID).json" | ConvertFrom-Json
    if (!$JSONOutput) {
        # Associate values to output bindings by calling 'Push-OutputBinding'.
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ Waiting = $true }
            })
        exit
    }
    else {
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = $JSONOutput
            })
        Remove-Item "Cache_BECCheck\$($Request.Query.GUID).json" -Force
        exit
    }
}
else {
    $RunningGUID = (New-Guid).GUID
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{ GUID = $RunningGUID }
        })
    $OrchRequest = [PSCustomObject]@{
        GUID         = $RunningGUID
        TenantFilter = $request.query.tenantfilter
        UserID       = $request.query.userid
    }
    $InstanceId = Start-NewOrchestration -FunctionName 'Durable_BECRun' -InputObject $OrchRequest

}
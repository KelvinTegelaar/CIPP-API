using namespace System.Net
# Input bindings are passed in via param block.
param($Request, $TriggerMetadata)

if ($request.query.GUID) {
    try {
        $JSONOutput = Get-Content "Cache_IncidentsCheck\$($Request.Query.GUID).json" -ErrorAction SilentlyContinue | ConvertFrom-Json
    }
    catch {
        Write-Host "Durable Function Incidents List JSON not Present Yet"
    }

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
        Remove-Item "Cache_IncidentsCheck\$($Request.Query.GUID).json" -Force
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
        GUID     = $RunningGUID
        TenantID = $Request.query.tenantFilter
    }
    $InstanceId = Start-NewOrchestration -FunctionName 'Durable_IncidentsRun' -InputObject $OrchRequest

}
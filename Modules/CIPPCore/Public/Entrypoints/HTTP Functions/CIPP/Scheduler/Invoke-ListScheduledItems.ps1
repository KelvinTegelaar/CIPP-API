using namespace System.Net

Function Invoke-ListScheduledItems {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    $Table = Get-CIPPTable -TableName 'ScheduledTasks'
    if ($Request.query.Showhidden -eq 'true') {
        $HiddenTasks = $false
    } else {
        $HiddenTasks = $true
    }
    $Tasks = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'ScheduledTask'" | Where-Object { $_.Hidden -ne $HiddenTasks }
    $ScheduledTasks = foreach ($Task in $tasks) {
        $Task.Parameters = $Task.Parameters | ConvertFrom-Json
        $Task
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($ScheduledTasks)
        })

}

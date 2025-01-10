using namespace System.Net

Function Invoke-ListScheduledItems {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Scheduler.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    $ScheduledItemFilter = [System.Collections.Generic.List[string]]::new()
    $ScheduledItemFilter.Add("PartitionKey eq 'ScheduledTask'")

    if ($Request.Query.ShowHidden) {
        $ScheduledItemFilter.Add('Hidden eq true')
    } else {
        $ScheduledItemFilter.Add('Hidden eq false')
    }

    if ($Request.Query.Name) {
        $ScheduledItemFilter.Add("Name eq '$($Request.Query.Name)'")
    }

    $Filter = $ScheduledItemFilter -join ' and '

    Write-Host "Filter: $Filter"
    $Table = Get-CIPPTable -TableName 'ScheduledTasks'
    if ($Request.Query.Showhidden -eq $true) {
        $HiddenTasks = $false
    } else {
        $HiddenTasks = $true
    }
    $Tasks = Get-CIPPAzDataTableEntity @Table -Filter $Filter | Where-Object { $_.Hidden -ne $HiddenTasks }
    if ($Request.Query.Type) {
        $tasks.Command
        $Tasks = $Tasks | Where-Object { $_.command -eq $Request.Query.Type }
    }

    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
    if ($AllowedTenants -notcontains 'AllTenants') {
        $Tasks = $Tasks | Where-Object -Property TenantId -In $AllowedTenants
    }
    $ScheduledTasks = foreach ($Task in $tasks) {
        if ($Task.Parameters) {
            $Task.Parameters = $Task.Parameters | ConvertFrom-Json -ErrorAction SilentlyContinue
        } else {
            $Task | Add-Member -NotePropertyName Parameters -NotePropertyValue @{}
        }
        $Task
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($ScheduledTasks)
        })

}

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

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'


    # Interact with query parameters or the body of the request.
    $ShowHidden = $Request.Query.ShowHidden ?? $Request.Body.ShowHidden
    $Name = $Request.Query.Name ?? $Request.Body.Name
    $Type = $Request.Query.Type ?? $Request.Body.Type

    $ScheduledItemFilter = [System.Collections.Generic.List[string]]::new()
    $ScheduledItemFilter.Add("PartitionKey eq 'ScheduledTask'")

    if ($ShowHidden -eq $true) {
        $ScheduledItemFilter.Add('Hidden eq true')
    } else {
        $ScheduledItemFilter.Add('Hidden eq false')
    }

    if ($Name -eq $true) {
        $ScheduledItemFilter.Add("Name eq '$($Name)'")
    }

    $Filter = $ScheduledItemFilter -join ' and '

    Write-Host "Filter: $Filter"
    $Table = Get-CIPPTable -TableName 'ScheduledTasks'
    if ($ShowHidden -eq $true) {
        $HiddenTasks = $false
    } else {
        $HiddenTasks = $true
    }
    $Tasks = Get-CIPPAzDataTableEntity @Table -Filter $Filter | Where-Object { $_.Hidden -ne $HiddenTasks }
    if ($Type) {
        $Tasks = $Tasks | Where-Object { $_.command -eq $Type }
    }

    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList

    if ($AllowedTenants -notcontains 'AllTenants') {
        $TenantList = Get-Tenants -IncludeErrors | Select-Object customerId, defaultDomainName
        $AllowedTenantDomains = $TenantList | Where-Object -Property customerId -In $AllowedTenants | Select-Object -ExpandProperty defaultDomainName
        $Tasks = $Tasks | Where-Object -Property Tenant -In $AllowedTenantDomains
    }
    $ScheduledTasks = foreach ($Task in $tasks) {
        if ($Task.Parameters) {
            $Task.Parameters = $Task.Parameters | ConvertFrom-Json -ErrorAction SilentlyContinue
        } else {
            $Task | Add-Member -NotePropertyName Parameters -NotePropertyValue @{}
        }
        if ($Task.Recurrence -eq 0 -or [string]::IsNullOrEmpty($Task.Recurrence)) {
            $Task.Recurrence = 'Once'
        }
        $Task
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($ScheduledTasks | Sort-Object -Property ExecutedTime -Descending)
        })

}

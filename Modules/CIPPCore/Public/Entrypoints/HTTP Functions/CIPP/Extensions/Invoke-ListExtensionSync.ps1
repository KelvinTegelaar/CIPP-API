using namespace System.Net

Function Invoke-ListExtensionSync {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Extension.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    $ScheduledTasksTable = Get-CIPPTable -TableName 'ScheduledTasks'
    $ScheduledTasks = Get-CIPPAzDataTableEntity @ScheduledTasksTable -Filter 'Hidden eq true' | Where-Object { $_.Command -match 'CippExtension' }

    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
    $TenantList = Get-Tenants -IncludeErrors
    $AllTasksArrayList = [system.collections.generic.list[object]]::new()

    foreach ($Task in $ScheduledTasks) {
        if ($Task.Results -and (Test-Json -Json $Task.Results -ErrorAction SilentlyContinue)) {
            $Results = $Task.Results | ConvertFrom-Json
        } else {
            $Results = $Task.Results
        }

        $TaskEntry = [PSCustomObject]@{
            RowKey        = $Task.RowKey
            PartitionKey  = $Task.PartitionKey
            Tenant        = $Task.Tenant
            Name          = $Task.Name
            SyncType      = $Task.SyncType
            ScheduledTime = $Task.ScheduledTime
            ExecutedTime  = $Task.ExecutedTime
            RepeatsEvery  = $Task.Recurrence
            Results       = $Results
        }

        if ($AllowedTenants -notcontains 'AllTenants') {
            $Tenant = $TenantList | Where-Object -Property defaultDomainName -EQ $Task.Tenant
            if ($AllowedTenants -contains $Tenant.customerId) {
                $AllTasksArrayList.Add($TaskEntry)
            }
        } else {
            $AllTasksArrayList.Add($TaskEntry)
        }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = ConvertTo-Json -Depth 5 -InputObject @($AllTasksArrayList)
        })
}

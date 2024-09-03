# Input bindings are passed in via param block.
param($Timer)

try {
    $Tenants = Get-Tenants -IncludeAll | Where-Object { $_.customerId -ne $env:TenantID -and $_.Excluded -eq $false }
    $CPVTable = Get-CIPPTable -TableName cpvtenants
    $CPVRows = Get-CIPPAzDataTableEntity @CPVTable
    $ModuleRoot = (Get-Module CIPPCore).ModuleBase
    $SAMManifest = Get-Item -Path "$ModuleRoot\Public\SAMManifest.json"
    $AdditionalPermissions = Get-Item -Path "$ModuleRoot\Public\AdditionalPermissions.json"
    $Tenants = $Tenants | ForEach-Object {
        $CPVRow = $CPVRows | Where-Object -Property Tenant -EQ $_.customerId
        if (!$CPVRow -or $env:ApplicationID -notin $CPVRow.applicationId -or $SAMManifest.LastWriteTime.ToUniversalTime() -gt $CPVRow.Timestamp.DateTime -or $AdditionalPermissions.LastWriteTime.ToUniversalTime() -ge $CPVRow.Timestamp.DateTime -or $CPVRow.Timestamp.DateTime -le (Get-Date).AddDays(-7).ToUniversalTime() -or !$_.defaultDomainName) {
            $_
        }
    }
    $TenantCount = ($Tenants | Measure-Object).Count
    if ($TenantCount -gt 0) {
        $Queue = New-CippQueueEntry -Name 'Update Permissions' -TotalTasks $TenantCount
        $TenantBatch = $Tenants | Select-Object defaultDomainName, customerId, displayName, @{n = 'FunctionName'; exp = { 'UpdatePermissionsQueue' } }, @{n = 'QueueId'; exp = { $Queue.RowKey } }
        $InputObject = [PSCustomObject]@{
            OrchestratorName = 'UpdatePermissionsOrchestrator'
            Batch            = @($TenantBatch)
        }
        $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
        Write-Host "Started permissions orchestration with ID = '$InstanceId'"
    } else {
        Write-Host 'No tenants require permissions update'
    }
} catch {}

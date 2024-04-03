# Input bindings are passed in via param block.
param($Timer)

try {
    $Tenants = Get-Tenants -IncludeErrors | Where-Object { $_.customerId -ne $env:TenantId } | ForEach-Object { $_ | Add-Member -NotePropertyName FunctionName -NotePropertyValue 'UpdatePermissionsQueue'; $_ }

    if (($Tenants | Measure-Object).Count -gt 0) {
        $InputObject = [PSCustomObject]@{
            OrchestratorName = 'UpdatePermissionsOrchestrator'
            Batch            = @($Tenants)
        }
        #Write-Host ($InputObject | ConvertTo-Json)
        $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5)
        Write-Host "Started permissions orchestration with ID = '$InstanceId'"
    }
} catch {}
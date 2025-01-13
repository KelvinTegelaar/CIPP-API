function Start-UpdatePermissionsOrchestrator {
    <#
    .SYNOPSIS
    Start the Update Permissions Orchestrator
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    try {
        Write-Information 'Updating Permissions'
        $Tenants = Get-Tenants -IncludeAll | Where-Object { $_.customerId -ne $env:TenantID -and $_.Excluded -eq $false }
        $CPVTable = Get-CIPPTable -TableName cpvtenants
        $CPVRows = Get-CIPPAzDataTableEntity @CPVTable
        $LastCPV = ($CPVRows | Sort-Object -Property Timestamp -Descending | Select-Object -First 1).Timestamp.DateTime
        Write-Information "CPV last updated at $LastCPV"

        $SAMPermissions = Get-CIPPSamPermissions
        Write-Information "SAM Permissions last updated at $($SAMPermissions.Timestamp)"

        $SAMRolesTable = Get-CIPPTable -TableName SAMRoles
        $SAMRoles = Get-CIPPAzDataTableEntity @SAMRolesTable
        Write-Information "SAM Roles last updated at $($SAMRoles.Timestamp.DateTime)"

        $Tenants = $Tenants | ForEach-Object {
            $CPVRow = $CPVRows | Where-Object -Property Tenant -EQ $_.customerId
            if (!$CPVRow -or $env:ApplicationID -notin $CPVRow.applicationId -or $SAMPermissions.Timestamp -gt $CPVRow.Timestamp.DateTime -or $CPVRow.Timestamp.DateTime -le (Get-Date).AddDays(-7).ToUniversalTime() -or !$_.defaultDomainName -or ($SAMroles.Timestamp.DateTime -gt $CPVRow.Timestamp.DateTime -and ($SAMRoles.Tenants -contains $_.defaultDomainName -or $SAMRoles.Tenants.value -contains $_.defaultDomainName -or $SAMRoles.Tenants -contains 'AllTenants' -or $SAMRoles.Tenants.value -contains 'AllTenants'))) {
                $_
            }
        }
        $TenantCount = ($Tenants | Measure-Object).Count

        if ($TenantCount -gt 0) {
            Write-Information "Found $TenantCount tenants that require permissions update"
            $Queue = New-CippQueueEntry -Name 'Update Permissions' -TotalTasks $TenantCount
            $TenantBatch = $Tenants | Select-Object defaultDomainName, customerId, displayName, @{n = 'FunctionName'; exp = { 'UpdatePermissionsQueue' } }, @{n = 'QueueId'; exp = { $Queue.RowKey } }
            $InputObject = [PSCustomObject]@{
                OrchestratorName = 'UpdatePermissionsOrchestrator'
                Batch            = @($TenantBatch)
            }
            Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
        } else {
            Write-Information 'No tenants require permissions update'
        }
    } catch {}
}

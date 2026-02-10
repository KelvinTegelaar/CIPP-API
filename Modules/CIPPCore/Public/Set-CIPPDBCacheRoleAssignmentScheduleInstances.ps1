function Set-CIPPDBCacheRoleAssignmentScheduleInstances {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        $RoleAssignmentScheduleInstances = New-GraphGetRequest -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleInstances' -tenantid $TenantFilter

        $Body = [pscustomobject]@{
            Tenant        = $TenantFilter
            LastRefresh   = (Get-Date).ToUniversalTime()
            Type          = 'RoleAssignmentScheduleInstances'
            Data          = [System.Text.Encoding]::UTF8.GetBytes(($RoleAssignmentScheduleInstances | ConvertTo-Json -Compress -Depth 10))
            PartitionKey  = 'TenantCache'
            RowKey        = ('{0}-{1}' -f $TenantFilter, 'RoleAssignmentScheduleInstances')
            SchemaVersion = [int]1
            SentAsDate    = [string](Get-Date -UFormat '+%Y-%m-%dT%H:%M:%S.000Z')
        }

        $null = Add-CIPPAzDataTableEntity @CacheTableDetails -Entity $Body -Force
        Write-LogMessage -API 'DBCache' -tenant $TenantFilter -message 'Role assignment schedule instances cache updated' -sev Debug
    } catch {
        Write-LogMessage -API 'DBCache' -tenant $TenantFilter -message "Error caching role assignment schedule instances: $($_.Exception.Message)" -sev Error
        throw
    }
}

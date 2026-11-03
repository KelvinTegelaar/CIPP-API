BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CippExtensions/Public/Extension Functions/Register-CippExtensionScheduledTasks.ps1')

    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-Tenants {
        param([switch]$IncludeErrors)
        @(
            [pscustomobject]@{ customerId = 'a'; defaultDomainName = 'a.test' }
            [pscustomobject]@{ customerId = 'b'; defaultDomainName = 'b.test' }
        )
    }
    function Add-CIPPScheduledTask { param($Task, $hidden, $SyncType) $script:Added.Add("$SyncType/$($Task.TenantFilter)") }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) $script:Removed.Add($Entity.RowKey) }
    function Get-CIPPAzDataTableEntity {
        param($TableName, $Filter)
        switch ($TableName) {
            'Extensionsconfig' {
                [pscustomobject]@{ config = (@{
                            Hudu    = @{ Enabled = $true }
                            Sherweb = @{ Enabled = $true; AutoMigrations = $true }
                        } | ConvertTo-Json -Compress)
                }
            }
            'ScheduledTasks' {
                @(
                    [pscustomobject]@{ PartitionKey = 'ScheduledTask'; RowKey = 'hudu-a'; Tenant = 'a.test'; SyncType = 'Hudu'; Command = 'Push-CippExtensionData'; Name = 'Hudu Extension Sync' }
                    [pscustomobject]@{ PartitionKey = 'ScheduledTask'; RowKey = 'cd-b'; Tenant = 'b.test'; SyncType = 'CustomData'; Command = 'Push-CippExtensionData'; Name = 'CustomData Extension Sync' }
                    [pscustomobject]@{ PartitionKey = 'ScheduledTask'; RowKey = 'sherweb-b'; Tenant = 'b.test'; SyncType = 'Sherweb'; Command = 'Invoke-SherwebMigration'; Name = 'Sherweb Migration Check' }
                )
            }
            'CippMapping' {
                switch ($Filter) {
                    "PartitionKey eq 'HuduMapping'" { @([pscustomobject]@{ RowKey = 'a'; IntegrationId = '1' }) }
                    "PartitionKey eq 'SherwebMapping'" { @([pscustomobject]@{ RowKey = 'b'; IntegrationId = '2' }) }
                    default { @() }
                }
            }
            default { @() }
        }
    }
}

Describe 'Register-CIPPExtensionScheduledTasks cleanup scope' {
    BeforeEach {
        $script:Added = [System.Collections.Generic.List[string]]::new()
        $script:Removed = [System.Collections.Generic.List[string]]::new()
    }

    It 'rescheduling one extension leaves other extensions tasks alone' {
        Register-CIPPExtensionScheduledTasks -Reschedule -Extensions 'Hudu' -InformationAction SilentlyContinue 3>$null
        $script:Added | Should -Be @('Hudu/a.test')
        # cd-b and sherweb-b belong to extensions that were not being processed.
        $script:Removed | Should -BeNullOrEmpty
    }
}

# A CIPP backup must carry the rows nothing else can recreate: CIPP users with manual roles,
# tenant exclusions and direct tenants. GDAP tenants are rebuilt from Graph and stay out.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-AzDataTableEntity {
        param($TableName, $Filter)
        switch ($TableName) {
            'allowedUsers' {
                [pscustomobject]@{ PartitionKey = 'User'; RowKey = 'tech@contoso.com'; ManualRoles = '["editor"]' }
                [pscustomobject]@{ PartitionKey = 'User'; RowKey = '_lastSync'; Value = 'x' }
            }
            'Tenants' {
                # The real table applies the filter; assert it asks for the right rows and serve them.
                $script:TenantFilterUsed = $Filter
                [pscustomobject]@{ PartitionKey = 'Tenants'; RowKey = 'direct-id'; customerId = 'direct-id'; defaultDomainName = 'direct.com'; initialDomainName = 'direct.onmicrosoft.com'; displayName = 'Direct'; delegatedPrivilegeStatus = 'directTenant'; directTenantUserPrincipalName = 'svc@direct.com'; directTenantAuthDate = [DateTimeOffset]::new(2026, 1, 1, 9, 30, 0, [TimeSpan]::Zero); Excluded = $false; LastGraphError = 'stale'; RequiresRefresh = $false }
                [pscustomobject]@{ PartitionKey = 'Tenants'; RowKey = 'excl-id'; customerId = 'excl-id'; defaultDomainName = 'excl.com'; displayName = 'Excluded'; delegatedPrivilegeStatus = 'granularDelegatedAdminPrivileges'; Excluded = $true; ExcludeUser = 'admin'; domains = 'a,b' }
            }
        }
    }
    function New-CIPPAzStorageRequest { }
    function Add-CIPPAzDataTableEntity { }
    function Write-LogMessage { }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Push-CIPPBackupReplication { param($BackupType, $BlobName, $Content, $Headers) $script:Captured = $Content }

    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/New-CIPPBackup.ps1')
    $null = New-CIPPBackup -backupType 'CIPP' -ConnectionString 'UseDevelopmentStorage=true'
    $script:Rows = $script:Captured | ConvertFrom-Json
}

Describe 'New-CIPPBackup CIPP backup contents' {
    It 'includes CIPP users and leaves out sync bookkeeping rows' {
        $Users = @($Rows | Where-Object table -EQ 'allowedUsers')
        $Users.Count | Should -Be 1
        $Users[0].RowKey | Should -Be 'tech@contoso.com'
        $Users[0].ManualRoles | Should -Be '["editor"]'
    }

    It 'asks the tenants table only for excluded and direct tenants' {
        $TenantFilterUsed | Should -Match "Excluded eq true or delegatedPrivilegeStatus eq 'directTenant'"
    }

    It 'keeps what a direct tenant needs and marks it for refresh' {
        $Direct = $Rows | Where-Object { $_.table -eq 'Tenants' -and $_.RowKey -eq 'direct-id' }
        $Direct.delegatedPrivilegeStatus | Should -Be 'directTenant'
        $Direct.initialDomainName | Should -Be 'direct.onmicrosoft.com'
        $Direct.directTenantUserPrincipalName | Should -Be 'svc@direct.com'
        $Direct.RequiresRefresh | Should -BeTrue
        $Direct.PSObject.Properties.Name | Should -Not -Contain 'LastGraphError'
    }

    It 'writes the direct tenant auth date as a UTC string, as the restore reads it' {
        $Direct = $script:Captured | ConvertFrom-Json -AsHashtable | Where-Object { $_.table -eq 'Tenants' -and $_.RowKey -eq 'direct-id' }
        $Direct.directTenantAuthDate.Kind | Should -Be 'Utc'
        $Direct.directTenantAuthDate | Should -Be ([datetime]::new(2026, 1, 1, 9, 30, 0, [DateTimeKind]::Utc))
    }

    It 'keeps an excluded tenant as exclusion state only' {
        $Excluded = $Rows | Where-Object { $_.table -eq 'Tenants' -and $_.RowKey -eq 'excl-id' }
        $Excluded.Excluded | Should -BeTrue
        $Excluded.PSObject.Properties.Name | Should -Not -Contain 'delegatedPrivilegeStatus'
        $Excluded.PSObject.Properties.Name | Should -Not -Contain 'domains'
    }
}

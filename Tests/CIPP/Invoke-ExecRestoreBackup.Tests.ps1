# Restore writes rows into the table each row names, so the table must be one a CIPP backup
# exports, role/credential tables need superadmin, and the caller must hold all tenants.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Settings/Invoke-ExecRestoreBackup.ps1'
    $BackupPath = Join-Path $BackendRoot 'Modules/CIPPCore/Public/New-CIPPBackup.ps1'

    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CippTable { param($tablename) }
    function Add-AzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Get-CIPPBackup { param($Type, $Name) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Test-CIPPAccessUserRole { param($User) $User }
    function Get-CippRequestAllowedPermissions { }
    function Test-CIPPAccess { param($Request, [switch]$TenantList) }

    . $FunctionPath

    # Tables New-CIPPBackup exports for a CIPP backup, read from its source.
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($BackupPath, [ref]$null, [ref]$null)
    $Assign = $Ast.Find({ param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq '$BackupTables' }, $true)
    $script:ExportedTables = @($Assign.Right.FindAll({ param($n) $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true).Value)

    function New-TestRequest {
        param($Body, [string[]]$HeaderRoles)
        $Principal = @{ userDetails = 'caller@contoso.com'; userRoles = $HeaderRoles } | ConvertTo-Json -Compress
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecRestoreBackup' }
            Headers = @{ 'x-ms-client-principal' = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Principal)) }
            Body    = $Body
            Query   = @{}
        }
    }

    function New-Row {
        param([string]$Table, [string]$RowKey = 'probe')
        [pscustomobject]@{ table = $Table; PartitionKey = 'probe'; RowKey = $RowKey }
    }
}

Describe 'Invoke-ExecRestoreBackup table access' {
    BeforeEach {
        $script:Written = [System.Collections.Generic.List[string]]::new()
        $script:Opened = [System.Collections.Generic.List[string]]::new()
        $script:Permissions = @('CIPP.AppSettings.ReadWrite')
        $script:TenantList = @('AllTenants')
        Mock Get-CippTable { $script:Opened.Add([string]$tablename); @{ TableName = $tablename } }
        Mock Add-AzDataTableEntity { $script:Written.Add([string]$TableName) }
        Mock Get-CippRequestAllowedPermissions { , $script:Permissions }
        Mock Test-CIPPAccess { $script:TenantList }
        Mock Write-LogMessage {}
    }

    Context 'admin caller' {
        It 'does not restore an allowedUsers row' {
            $Response = Invoke-ExecRestoreBackup -Request (New-TestRequest -Body @(New-Row 'allowedUsers') -HeaderRoles 'admin') -TriggerMetadata $null
            $script:Written | Should -Not -Contain 'allowedUsers'
            $Response.Body.Results | Should -Match 'allowedUsers'
        }

        It 'does not restore an ApiClients row, whatever the casing' {
            $Rows = @((New-Row 'ApiClients'), (New-Row 'APICLIENTS' 'probe2'))
            $null = Invoke-ExecRestoreBackup -Request (New-TestRequest -Body $Rows -HeaderRoles 'admin') -TriggerMetadata $null
            $script:Written.Count | Should -Be 0
        }

        It 'still cannot restore the tables that already required superadmin' {
            $Rows = @('AccessRoleGroups', 'allowedAppRoles', 'AccessIPRanges', 'CustomRoles', 'DevSecrets' | ForEach-Object { New-Row $_ })
            $null = Invoke-ExecRestoreBackup -Request (New-TestRequest -Body $Rows -HeaderRoles 'admin') -TriggerMetadata $null
            $script:Written.Count | Should -Be 0
        }

        It 'never opens or writes a table a CIPP backup does not contain' {
            $null = Invoke-ExecRestoreBackup -Request (New-TestRequest -Body @(New-Row 'SomethingNew') -HeaderRoles 'admin') -TriggerMetadata $null
            $script:Opened | Should -Not -Contain 'SomethingNew'
            $script:Written.Count | Should -Be 0
        }

        It 'restores ordinary backup tables and reports the skipped ones' {
            $Rows = @((New-Row 'templates'), (New-Row 'Config'), (New-Row 'ScheduledTasks'), (New-Row 'standards'), (New-Row 'ApiClients'))
            $Response = Invoke-ExecRestoreBackup -Request (New-TestRequest -Body $Rows -HeaderRoles 'admin') -TriggerMetadata $null
            @($script:Written) | Should -Be @('templates', 'Config', 'ScheduledTasks', 'standards')
            $Response.StatusCode | Should -Be 200
            $Response.Body.Results | Should -Match 'Successfully restored 4 rows'
            $Response.Body.Results | Should -Match 'ApiClients'
        }

        It 'applies the same rules to a stored backup restored by name' {
            $Stored = @((New-Row 'templates'), (New-Row 'allowedUsers'), (New-Row 'ApiClients')) | ConvertTo-Json -Compress
            Mock Get-CIPPBackup { [pscustomobject]@{ Backup = $Stored } }
            $null = Invoke-ExecRestoreBackup -Request (New-TestRequest -Body ([pscustomobject]@{ BackupName = 'CippBackup_x' }) -HeaderRoles 'admin') -TriggerMetadata $null
            @($script:Written) | Should -Be @('templates')
        }
    }

    Context 'superadmin caller' {
        BeforeEach { $script:Permissions = @('CIPP.AppSettings.ReadWrite', 'CIPP.SuperAdmin.ReadWrite') }

        It 'finds the role tables and their IP ranges in what New-CIPPBackup exports' {
            # A restored role without its IP ranges would work from any address.
            $script:ExportedTables | Should -Contain 'CustomRoles'
            $script:ExportedTables | Should -Contain 'AccessIPRanges'
        }

        It 'restores every table New-CIPPBackup exports' {
            $script:ExportedTables.Count | Should -BeGreaterThan 20
            $Rows = @($script:ExportedTables | ForEach-Object { New-Row $_ })
            $null = Invoke-ExecRestoreBackup -Request (New-TestRequest -Body $Rows -HeaderRoles 'superadmin') -TriggerMetadata $null
            @($script:Written) | Should -Be $script:ExportedTables
        }

        It 'still refuses a table that is not part of a CIPP instance backup' {
            $null = Invoke-ExecRestoreBackup -Request (New-TestRequest -Body @(New-Row 'SomethingNew') -HeaderRoles 'superadmin') -TriggerMetadata $null
            $script:Written.Count | Should -Be 0
        }

        It 'does not restore DevSecrets, which no backup contains' {
            $Response = Invoke-ExecRestoreBackup -Request (New-TestRequest -Body @(New-Row 'DevSecrets') -HeaderRoles 'superadmin') -TriggerMetadata $null
            $script:Written | Should -Not -Contain 'DevSecrets'
            $Response.Body.Results | Should -Match 'DevSecrets'
        }

        It 'restores an allowedUsers row' {
            $null = Invoke-ExecRestoreBackup -Request (New-TestRequest -Body @(New-Row 'allowedUsers') -HeaderRoles 'superadmin') -TriggerMetadata $null
            $script:Written | Should -Contain 'allowedUsers'
        }

        It 'is treated as its impersonated role' {
            # Request permissions follow the impersonated role; the signed-in principal still says superadmin.
            $script:Permissions = @('CIPP.AppSettings.ReadWrite')
            $null = Invoke-ExecRestoreBackup -Request (New-TestRequest -Body @(New-Row 'ApiClients') -HeaderRoles 'superadmin') -TriggerMetadata $null
            $script:Written.Count | Should -Be 0
        }
    }

    Context 'caller limited to some tenants' {
        It 'refuses the whole restore before writing anything' {
            $script:TenantList = @('customer-a')
            $Response = Invoke-ExecRestoreBackup -Request (New-TestRequest -Body @(New-Row 'templates') -HeaderRoles 'authenticated', 'restore-role') -TriggerMetadata $null
            $Response.StatusCode | Should -Be 403
            $script:Written.Count | Should -Be 0
        }
    }
}

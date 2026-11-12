# Pester tests for who may read which backups through Invoke-ExecListBackup.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    $script:AllTenants = @(
        [pscustomobject]@{ customerId = 'tenant-1'; defaultDomainName = 'contoso.com' }
        [pscustomobject]@{ customerId = 'tenant-2'; defaultDomainName = 'fabrikam.com' }
    )
    function Get-Tenants {
        param($TenantFilter, [switch]$IncludeErrors)
        $script:AllTenants.Where({ $null -eq $script:CippAllowedTenantsStorage.Value -or $script:CippAllowedTenantsStorage.Value -contains $_.customerId })
    }
    function Get-CIPPBackup { param($Type, $TenantFilter, $Name, [switch]$NameOnly) }
    function Test-CIPPAccess { param($Request, [switch]$TenantList) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Select-CippAllowedTenantData.ps1')
    $Endpoint = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Core/Invoke-ExecListBackup.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $Endpoint -Raw)))

    function Invoke-List {
        param([hashtable]$Query)
        Invoke-ExecListBackup -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecListBackup' }; Headers = @{}; Query = [pscustomobject]$Query; Body = [pscustomobject]@{} })
    }
}

Describe 'ExecListBackup' {
    BeforeEach {
        $script:CippAllowedTenantsStorage = [pscustomobject]@{ Value = $null }
        $script:CanManageBackups = $true
        Mock Test-CIPPAccess {
            if ($TenantList) { return ($script:CippAllowedTenantsStorage.Value ?? @('AllTenants')) }
            if (-not $script:CanManageBackups) { throw 'Access to this CIPP API endpoint is not allowed' }
            $true
        }
        Mock Get-CIPPBackup {
            if ($Type -eq 'Scheduled') {
                if ($NameOnly) {
                    [pscustomobject]@{ RowKey = 'contoso.com_2026-11-01'; Timestamp = [datetime]'2026-11-01'; users = 'x' }
                    [pscustomobject]@{ RowKey = 'fabrikam.com_2026-11-01'; Timestamp = [datetime]'2026-11-01'; users = 'x' }
                } else {
                    [pscustomobject]@{ RowKey = 'contoso.com_2026-11-01'; TenantFilter = 'contoso.com'; Backup = '{}' }
                    [pscustomobject]@{ RowKey = 'fabrikam.com_2026-11-01'; TenantFilter = 'fabrikam.com'; Backup = '{}' }
                }
            } else {
                [pscustomobject]@{ RowKey = 'CIPPBackup_2026-11-01'; Timestamp = [datetime]'2026-11-01'; Backup = '[{"table":"ApiClients"}]' }
            }
        }
    }

    Context 'CIPP configuration backups' {
        It 'are refused to a caller who cannot run CIPP backups, for <Name>' -ForEach @(
            @{ Name = 'the default type'; Query = @{ NameOnly = 'true' } }
            @{ Name = 'a named backup'; Query = @{ BackupName = 'CIPPBackup_2026-11-01' } }
            @{ Name = 'Type=CIPP'; Query = @{ Type = 'CIPP' } }
        ) {
            $script:CanManageBackups = $false
            $Response = Invoke-List -Query $Query
            $Response.StatusCode | Should -Be 403
            Should -Invoke Get-CIPPBackup -Times 0 -Exactly
        }

        It 'are refused to a caller limited to some tenants even with the permission' {
            $script:CippAllowedTenantsStorage.Value = @('tenant-1')
            (Invoke-List -Query @{ NameOnly = 'true' }).StatusCode | Should -Be 403
            Should -Invoke Get-CIPPBackup -Times 0 -Exactly
        }

        It 'are returned to a caller who can run CIPP backups and has every tenant' {
            $Response = Invoke-List -Query @{ BackupName = 'CIPPBackup_2026-11-01' }
            $Response.StatusCode | Should -Be 200
            @($Response.Body).Count | Should -Be 1
        }
    }

    Context 'tenant backups' {
        It 'returns only the caller tenants, for <Name>' -ForEach @(
            @{ Name = 'names only'; Query = @{ Type = 'Scheduled'; NameOnly = 'true' } }
            @{ Name = 'full rows'; Query = @{ Type = 'Scheduled' } }
            @{ Name = 'a named backup of another tenant'; Query = @{ Type = 'Scheduled'; BackupName = 'fabrikam.com_2026-11-01' } }
        ) {
            $script:CippAllowedTenantsStorage.Value = @('tenant-1')
            $script:CanManageBackups = $false
            $Response = Invoke-List -Query $Query
            $Response.StatusCode | Should -Be 200
            $Rows = @($Response.Body)
            @($Rows | ForEach-Object { "$($_.BackupName)$($_.RowKey)" }) -match 'fabrikam' | Should -BeNullOrEmpty
            $Rows.Count | Should -Be 1
        }

        It 'returns every tenant to a caller with every tenant' {
            $script:CanManageBackups = $false
            @((Invoke-List -Query @{ Type = 'Scheduled'; NameOnly = 'true' }).Body).Count | Should -Be 2
        }
    }

    It 'refuses a Type that is not a backup type' {
        (Invoke-List -Query @{ Type = 'ApiClients' }).StatusCode | Should -Be 400
        Should -Invoke Get-CIPPBackup -Times 0 -Exactly
    }
}

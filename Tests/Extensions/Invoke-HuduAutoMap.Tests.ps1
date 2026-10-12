BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity {
        [pscustomobject]@{ config = (@{ Hudu = @{ Enabled = $true; BaseURL = 'https://hudu.example.com' } } | ConvertTo-Json -Compress) }
    }
    function Connect-HuduAPI { param($configuration) }
    function Get-NormalizedError { param($Message) $Message }
    function Write-LogMessage { param($API, $tenant, $message, $Sev) }
    function Register-CIPPExtensionScheduledTasks { $script:Registered++ }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) $script:Added.Add($Entity) }
    function Get-ExtensionMapping {
        param($Extension)
        if ($Extension -eq 'Halo') {
            @(
                [pscustomobject]@{ RowKey = 't-halo'; IntegrationId = '1033' }
                [pscustomobject]@{ RowKey = 't-dup'; IntegrationId = '50' }
            )
        } else {
            @([pscustomobject]@{ RowKey = 't-mapped'; IntegrationId = '9' })
        }
    }
    function Get-Tenants {
        param([switch]$IncludeErrors)
        @(
            [pscustomobject]@{ customerId = 't-mapped'; displayName = 'Mapped'; defaultDomainName = 'mapped.test' }
            [pscustomobject]@{ customerId = 't-halo'; displayName = 'Contoso'; defaultDomainName = 'contoso.test' }
            [pscustomobject]@{ customerId = 't-name'; displayName = 'Fabrikam'; defaultDomainName = 'fabrikam.test' }
            [pscustomobject]@{ customerId = 't-dup'; displayName = 'Duplicate'; defaultDomainName = 'dup.test' }
            [pscustomobject]@{ customerId = 't-archived'; displayName = 'Old Co'; defaultDomainName = 'old.test' }
        )
    }
    function New-Company($Id, $Name, $HaloId, [bool]$Archived = $false) {
        [pscustomobject]@{
            id           = $Id
            name         = $Name
            archived     = $Archived
            integrations = @(if ($HaloId) { [pscustomobject]@{ integrator_name = 'halo'; sync_id = $HaloId; identifier = "$HaloId" } })
        }
    }

    . (Join-Path $RepoRoot 'Modules/CippExtensions/Public/Hudu/Invoke-HuduAutoMap.ps1')
}

Describe 'Invoke-HuduAutoMap' {
    BeforeEach {
        $script:Added = [System.Collections.Generic.List[object]]::new()
        $script:Registered = 0
    }

    Context 'Hudu returns companies synced from HaloPSA' {
        BeforeEach {
            function Get-HuduCompanies {
                @(
                    New-Company 9 'Mapped' 9
                    New-Company 11 'Contoso Group' 1033
                    New-Company 12 'Contoso' 7
                    New-Company 20 'Fabrikam' $null
                    New-Company 30 'Duplicate' 50
                    New-Company 31 'Duplicate Holdings' 50
                    New-Company 40 'Old Co' $null $true
                )
            }
            $script:Result = Invoke-HuduAutoMap -CIPPMapping @{}
            $script:ByTenant = @{}
            foreach ($Row in $script:Added) { $script:ByTenant[$Row.RowKey] = $Row }
        }

        It 'maps through the tenant''s HaloPSA client ahead of a company with the same name' {
            $script:ByTenant['t-halo'].IntegrationId | Should -Be '11'
        }

        It 'falls back to an exact company name match when the tenant has no HaloPSA client' {
            $script:ByTenant['t-name'].IntegrationId | Should -Be '20'
            $script:ByTenant['t-name'].SyncPasswords | Should -BeTrue
        }

        It 'skips a tenant whose HaloPSA client is on several Hudu companies' {
            $script:ByTenant.ContainsKey('t-dup') | Should -BeFalse
            $script:Result | Should -BeLike '*Duplicate (HaloPSA client 50 on 2 companies)*'
        }

        It 'ignores archived companies' {
            $script:ByTenant.ContainsKey('t-archived') | Should -BeFalse
        }

        It 'never rewrites an existing mapping and registers sync tasks for the new ones' {
            $script:ByTenant.ContainsKey('t-mapped') | Should -BeFalse
            $script:Added.Count | Should -Be 2
            $script:Registered | Should -Be 1
        }
    }

    It 'does not touch sync tasks when nothing new was mapped' {
        function Get-HuduCompanies { @(New-Company 9 'Mapped' 9) }

        $null = Invoke-HuduAutoMap -CIPPMapping @{}

        $script:Added.Count | Should -Be 0
        $script:Registered | Should -Be 0
    }
}

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity {
        [pscustomobject]@{ config = (@{ HaloPSA = @{ ResourceURL = 'https://halo.example.com/api'; ClientID = 'x' } } | ConvertTo-Json -Compress) }
    }
    function Get-HaloToken { param($configuration) @{ access_token = 'token' } }
    function Get-CippUserAgent { 'CIPP/test' }
    function Get-NormalizedError { param($Message) $Message }
    function Write-LogMessage { param($API, $tenant, $message, $Sev) }
    function Get-ExtensionMapping { param($Extension) @([pscustomobject]@{ RowKey = 'aaaaaaaa-0000-0000-0000-000000000001'; IntegrationId = '99' }) }
    function Get-Tenants {
        param([switch]$IncludeErrors)
        @(
            [pscustomobject]@{ customerId = 'aaaaaaaa-0000-0000-0000-000000000001'; displayName = 'Already'; defaultDomainName = 'already.test' }
            [pscustomobject]@{ customerId = 'aaaaaaaa-0000-0000-0000-000000000002'; displayName = 'Contoso'; defaultDomainName = 'contoso.test' }
            [pscustomobject]@{ customerId = 'aaaaaaaa-0000-0000-0000-000000000003'; displayName = 'Fabrikam'; defaultDomainName = 'fabrikam.test' }
            [pscustomobject]@{ customerId = 'aaaaaaaa-0000-0000-0000-000000000004'; displayName = 'Twins'; defaultDomainName = 'twins.test' }
            [pscustomobject]@{ customerId = 'aaaaaaaa-0000-0000-0000-000000000005'; displayName = 'Shared'; defaultDomainName = 'shared.test' }
        )
    }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) $script:Added.Add($Entity) }

    . (Join-Path $RepoRoot 'Modules/CippExtensions/Public/Halo/Invoke-HaloAutoMap.ps1')

    $script:Clients = @{
        record_count = 6
        clients      = @(
            [pscustomobject]@{ id = 1; name = 'Already' }
            [pscustomobject]@{ id = 2; name = 'Contoso' }
            [pscustomobject]@{ id = 3; name = 'Fabrikam' }
            [pscustomobject]@{ id = 4; name = 'Twins' }
            [pscustomobject]@{ id = 5; name = 'Twins' }
            [pscustomobject]@{ id = 7; name = 'Fabrikam Holdings' }
        )
    }
    $script:Detail = [pscustomobject]@{
        mappings_client = @(
            [pscustomobject]@{ azure_tenant_id = 'AAAAAAAA-0000-0000-0000-000000000001'; client_id = 1; client_name = 'Already' }
            [pscustomobject]@{ azure_tenant_id = 'aaaaaaaa-0000-0000-0000-000000000003'; client_id = 7; client_name = 'Fabrikam Holdings' }
            [pscustomobject]@{ azure_tenant_id = 'aaaaaaaa-0000-0000-0000-000000000005'; client_id = 2; client_name = 'Contoso' }
            [pscustomobject]@{ azure_tenant_id = 'aaaaaaaa-0000-0000-0000-000000000005'; client_id = 3; client_name = 'Fabrikam' }
        )
    }
}

Describe 'Invoke-HaloAutoMap' {
    BeforeEach {
        $script:Added = [System.Collections.Generic.List[object]]::new()
    }

    Context 'Halo returns tenant IDs and clients' {
        BeforeEach {
            Mock Invoke-RestMethod {
                if ($Uri -like '*/Client?*') { return $script:Clients }
                if ($Uri -like '*/AzureADConnection/*') { return $script:Detail }
                , @([pscustomobject]@{ id = 10 })
            }
            $script:Result = Invoke-HaloAutoMap -CIPPMapping @{}
            $script:ByTenant = @{}
            foreach ($Row in $script:Added) { $script:ByTenant[$Row.RowKey] = $Row.IntegrationId }
        }

        It 'prefers the tenant ID match over a client with the same name' {
            $script:ByTenant['aaaaaaaa-0000-0000-0000-000000000003'] | Should -Be '7'
        }

        It 'falls back to an exact client name match when Halo has no tenant ID for the tenant' {
            $script:ByTenant['aaaaaaaa-0000-0000-0000-000000000002'] | Should -Be '2'
        }

        It 'skips a tenant whose name is shared by several Halo clients' {
            $script:ByTenant.ContainsKey('aaaaaaaa-0000-0000-0000-000000000004') | Should -BeFalse
            $script:Result | Should -BeLike '*Twins (name shared by 2 clients)*'
        }

        It 'skips a tenant whose ID is on several Halo clients instead of falling back to its name' {
            $script:ByTenant.ContainsKey('aaaaaaaa-0000-0000-0000-000000000005') | Should -BeFalse
            $script:Result | Should -BeLike '*Shared (tenant ID on*'
        }

        It 'never rewrites an existing mapping' {
            $script:ByTenant.ContainsKey('aaaaaaaa-0000-0000-0000-000000000001') | Should -BeFalse
            $script:Added.Count | Should -Be 2
        }
    }

    It 'still maps by name when the Azure tenant integration cannot be read' {
        Mock Invoke-RestMethod {
            if ($Uri -like '*/Client?*') { return $script:Clients }
            throw 'Forbidden'
        }

        $Result = Invoke-HaloAutoMap -CIPPMapping @{}

        $script:Added.RowKey | Should -Contain 'aaaaaaaa-0000-0000-0000-000000000002'
        $script:Added.RowKey | Should -Contain 'aaaaaaaa-0000-0000-0000-000000000003'
        $Result | Should -BeLike '*only name matches were used*'
    }
}

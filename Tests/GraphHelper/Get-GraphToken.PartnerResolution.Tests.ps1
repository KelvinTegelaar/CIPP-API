# Pester tests for Get-GraphToken partner resolution
#
# Which refresh token goes into the token request decides which CSP the call authenticates as.
# The real Resolve-CIPPOwningPartner / Get-CIPPPartnerTenant / Get-CIPPPartnerRefreshToken are
# dot-sourced alongside the function under test so the partner-<guid> secret path is exercised
# end to end; only the storage, Key Vault and HTTP edges are mocked.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-GraphToken.ps1'
    $PrivateRoot = Join-Path $RepoRoot 'Modules/CIPPCore/Private'
    foreach ($Required in @($FunctionPath,
            (Join-Path $PrivateRoot 'Resolve-CIPPOwningPartner.ps1'),
            (Join-Path $PrivateRoot 'Get-CIPPPartnerTenant.ps1'),
            (Join-Path $PrivateRoot 'Get-CIPPPartnerRefreshToken.ps1'))) {
        if (-not (Test-Path -LiteralPath $Required)) { throw "Could not locate $Required" }
    }

    # Minimal stubs so Mock has commands to replace during tests
    function Get-CippTable { param($tablename, $Context) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Context, $Filter) }
    function Get-AzDataTableEntity { param($TableName, $Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force) }
    function Update-AzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force) }
    function Invoke-CIPPRestMethod { param($Method, $Uri, $Body, $ContentType) }
    function Get-CIPPAuthentication { }
    function Get-CIPPFeatureFlag { param($Id) }
    function Get-CippKeyVaultName { }
    function Get-CippKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) }

    . (Join-Path $PrivateRoot 'Get-CIPPPartnerTenant.ps1')
    . (Join-Path $PrivateRoot 'Get-CIPPPartnerRefreshToken.ps1')
    . (Join-Path $PrivateRoot 'Resolve-CIPPOwningPartner.ps1')
    . $FunctionPath

    $script:PrimaryPartner = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    $script:PartnerB = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
    $script:CustomerOfPrimary = '11111111-1111-1111-1111-111111111111'
    $script:CustomerOfB = '22222222-2222-2222-2222-222222222222'
    $script:DirectTenant = '44444444-4444-4444-4444-444444444444'
    $script:PrimaryToken = 'primary-refresh-token'
    $script:PartnerBToken = 'partner-b-refresh-token'
}

Describe 'Get-GraphToken partner resolution' {
    BeforeEach {
        $script:OriginalEnv = @{
            TenantID          = $env:TenantID
            RefreshToken      = $env:RefreshToken
            ApplicationID     = $env:ApplicationID
            ApplicationSecret = $env:ApplicationSecret
            SetFromProfile    = $env:SetFromProfile
            AzureWebJobsStorage = $env:AzureWebJobsStorage
            NonLocalHostAzurite = $env:NonLocalHostAzurite
        }
        $env:TenantID = $script:PrimaryPartner
        $env:RefreshToken = $script:PrimaryToken
        $env:ApplicationID = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
        $env:ApplicationSecret = 'stub-app-secret'
        $env:SetFromProfile = 'true'
        $env:AzureWebJobsStorage = 'DefaultEndpointsProtocol=https;AccountName=stub'
        $env:NonLocalHostAzurite = $null

        $script:MultiPartnerEnabled = $true
        $script:PartnerRows = [System.Collections.Generic.List[object]]::new()
        $script:TenantRows = [System.Collections.Generic.List[object]]::new()
        $script:KeyVaultSecrets = @{}
        $script:SentBodies = [System.Collections.Generic.List[object]]::new()

        Mock -CommandName Get-CIPPAuthentication -MockWith { }
        Mock -CommandName ConvertTo-CIPPODataFilterValue -MockWith { $Value }
        Mock -CommandName Get-CippTable -MockWith { @{ TableName = $tablename } }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Update-AzDataTableEntity -MockWith { }
        Mock -CommandName Get-AzDataTableEntity -MockWith { @() }
        Mock -CommandName Get-CippKeyVaultName -MockWith { 'stub-vault' }

        Mock -CommandName Get-CIPPFeatureFlag -MockWith {
            [pscustomobject]@{ Id = $Id; Enabled = $script:MultiPartnerEnabled }
        }

        Mock -CommandName Get-CippKeyVaultSecret -MockWith {
            if ($script:KeyVaultSecrets.ContainsKey($Name)) { return $script:KeyVaultSecrets[$Name] }
            throw "SecretNotFound: $Name"
        }

        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            if ($Filter -like '*AppCache*') { return @() }
            if ($Filter -like "*PartitionKey eq 'Partners'*") { return @($script:PartnerRows) }
            if ($Filter -like "*delegatedPrivilegeStatus eq 'directTenant'*") {
                return @($script:TenantRows | Where-Object { $_.delegatedPrivilegeStatus -eq 'directTenant' })
            }
            return @($script:TenantRows | Where-Object {
                    $Filter -like "*'$($_.RowKey)'*" -or $Filter -like "*'$($_.defaultDomainName)'*"
                })
        }

        Mock -CommandName Invoke-CIPPRestMethod -MockWith {
            $script:SentBodies.Add($Body)
            [pscustomobject]@{ access_token = 'stub-access-token'; expires_in = 3600 }
        }
    }

    AfterEach {
        foreach ($Key in $script:OriginalEnv.Keys) {
            Set-Item -Path "env:\$Key" -Value $script:OriginalEnv[$Key] -Force -ErrorAction SilentlyContinue
        }
        foreach ($Name in @("partner-$script:PartnerB", "partner-$script:PrimaryPartner", $script:DirectTenant)) {
            Remove-Item -Path "env:\$Name" -ErrorAction SilentlyContinue
        }
    }

    Context 'Customer owned by an additional partner' {
        BeforeEach {
            $script:PartnerRows.Add([pscustomobject]@{ PartitionKey = 'Partners'; RowKey = $script:PrimaryPartner; Enabled = $true })
            $script:PartnerRows.Add([pscustomobject]@{ PartitionKey = 'Partners'; RowKey = $script:PartnerB; Enabled = $true })
            $script:TenantRows.Add([pscustomobject]@{
                    PartitionKey             = 'Tenants'
                    RowKey                   = $script:CustomerOfB
                    customerId               = $script:CustomerOfB
                    defaultDomainName        = 'customer-b.onmicrosoft.com'
                    partnerTenantId          = $script:PartnerB
                    delegatedPrivilegeStatus = 'granularDelegatedAdminPrivileges'
                })
            $script:KeyVaultSecrets["partner-$script:PartnerB"] = $script:PartnerBToken
        }

        It 'authenticates with the owning partner refresh token' {
            $null = Get-GraphToken -tenantid $script:CustomerOfB -SkipCache $true

            $script:SentBodies.Count | Should -Be 1
            $script:SentBodies[0].refresh_token | Should -Be $script:PartnerBToken
        }

        It 'reads the partner secret whose name is partner- plus the partner tenant id' {
            $null = Get-GraphToken -tenantid $script:CustomerOfB -SkipCache $true

            Should -Invoke -CommandName Get-CippKeyVaultSecret -Times 1 -Exactly -ParameterFilter {
                $Name -eq "partner-bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
            }
        }

        It 'falls back to the primary token when the partner has no stored secret' {
            $script:KeyVaultSecrets.Remove("partner-$script:PartnerB")

            $null = Get-GraphToken -tenantid $script:CustomerOfB -SkipCache $true

            $script:SentBodies[0].refresh_token | Should -Be $script:PrimaryToken
        }
    }

    Context 'Customer with no partner assigned' {
        BeforeEach {
            $script:PartnerRows.Add([pscustomobject]@{ PartitionKey = 'Partners'; RowKey = $script:PrimaryPartner; Enabled = $true })
            $script:PartnerRows.Add([pscustomobject]@{ PartitionKey = 'Partners'; RowKey = $script:PartnerB; Enabled = $true })
        }

        It 'uses the primary environment token when partnerTenantId is blank' {
            $script:TenantRows.Add([pscustomobject]@{
                    PartitionKey             = 'Tenants'
                    RowKey                   = $script:CustomerOfPrimary
                    customerId               = $script:CustomerOfPrimary
                    defaultDomainName        = 'customer-a.onmicrosoft.com'
                    partnerTenantId          = ''
                    delegatedPrivilegeStatus = 'granularDelegatedAdminPrivileges'
                })

            $null = Get-GraphToken -tenantid $script:CustomerOfPrimary -SkipCache $true

            $script:SentBodies[0].refresh_token | Should -Be $script:PrimaryToken
            Should -Invoke -CommandName Get-CippKeyVaultSecret -Times 0 -Exactly
        }

        It 'uses the primary environment token when the tenant has no cached row at all' {
            $null = Get-GraphToken -tenantid $script:CustomerOfPrimary -SkipCache $true

            $script:SentBodies[0].refresh_token | Should -Be $script:PrimaryToken
            Should -Invoke -CommandName Get-CippKeyVaultSecret -Times 0 -Exactly
        }
    }

    Context 'The partner tenant itself' {
        BeforeEach {
            $script:PartnerRows.Add([pscustomobject]@{ PartitionKey = 'Partners'; RowKey = $script:PrimaryPartner; Enabled = $true })
            $script:PartnerRows.Add([pscustomobject]@{ PartitionKey = 'Partners'; RowKey = $script:PartnerB; Enabled = $true })
            $script:KeyVaultSecrets["partner-$script:PartnerB"] = $script:PartnerBToken
        }

        It 'uses an additional partner own token when the target is that partner tenant' {
            $null = Get-GraphToken -tenantid $script:PartnerB -SkipCache $true

            $script:SentBodies[0].refresh_token | Should -Be $script:PartnerBToken
        }

        It 'uses the environment token when the target is the primary partner tenant' {
            $null = Get-GraphToken -tenantid $script:PrimaryPartner -SkipCache $true

            $script:SentBodies[0].refresh_token | Should -Be $script:PrimaryToken
            Should -Invoke -CommandName Get-CippKeyVaultSecret -Times 0 -Exactly
        }
    }

    Context 'Direct tenants' {
        BeforeEach {
            $script:PartnerRows.Add([pscustomobject]@{ PartitionKey = 'Partners'; RowKey = $script:PrimaryPartner; Enabled = $true })
            $script:PartnerRows.Add([pscustomobject]@{ PartitionKey = 'Partners'; RowKey = $script:PartnerB; Enabled = $true })
            $script:TenantRows.Add([pscustomobject]@{
                    PartitionKey             = 'Tenants'
                    RowKey                   = $script:DirectTenant
                    customerId               = $script:DirectTenant
                    defaultDomainName        = 'direct.onmicrosoft.com'
                    partnerTenantId          = $script:PartnerB
                    delegatedPrivilegeStatus = 'directTenant'
                })
        }

        It 'keeps using the tenant own stored token, not a partner token' {
            Set-Item -Path "env:\$script:DirectTenant" -Value 'direct-tenant-token' -Force
            $script:KeyVaultSecrets["partner-$script:PartnerB"] = $script:PartnerBToken

            $null = Get-GraphToken -tenantid $script:DirectTenant -SkipCache $true

            $script:SentBodies[0].refresh_token | Should -Be 'direct-tenant-token'
            Should -Invoke -CommandName Get-CippKeyVaultSecret -Times 0 -Exactly
        }

        It 'lazily loads the direct tenant secret from Key Vault by tenant id' {
            $script:KeyVaultSecrets[$script:DirectTenant] = 'direct-tenant-token'

            $null = Get-GraphToken -tenantid $script:DirectTenant -SkipCache $true

            $script:SentBodies[0].refresh_token | Should -Be 'direct-tenant-token'
            Should -Invoke -CommandName Get-CippKeyVaultSecret -Times 1 -Exactly -ParameterFilter {
                $Name -eq '44444444-4444-4444-4444-444444444444'
            }
        }
    }

    Context 'MultiPartner flag disabled' {
        It 'behaves like the pre-branch default: environment token, no partner lookups' {
            $script:MultiPartnerEnabled = $false
            $script:TenantRows.Add([pscustomobject]@{
                    PartitionKey             = 'Tenants'
                    RowKey                   = $script:CustomerOfPrimary
                    customerId               = $script:CustomerOfPrimary
                    defaultDomainName        = 'customer-a.onmicrosoft.com'
                    partnerTenantId          = ''
                    delegatedPrivilegeStatus = 'granularDelegatedAdminPrivileges'
                })

            $null = Get-GraphToken -tenantid $script:CustomerOfPrimary -SkipCache $true

            $script:SentBodies[0].refresh_token | Should -Be $script:PrimaryToken
            Should -Invoke -CommandName Get-CippKeyVaultSecret -Times 0 -Exactly
            Should -Invoke -CommandName Get-CippTable -Times 0 -Exactly -ParameterFilter {
                $tablename -eq 'PartnerTenants'
            }
        }
    }
}

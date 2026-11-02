# Pester tests for Test-CIPPAccessTenant
# Verifies that direct tenants are assessed on their own connectivity instead of on GDAP role
# assignments made to the partner tenant, and that the GDAP path is unchanged.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPAccessTenant.ps1'

    # Minimal stubs so Mock has commands to replace during tests
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-GraphBulkRequest { param($tenantid, $Requests) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams) }
    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function Write-LogMessage { param($headers, $API, $tenant, $tenantId, $message, $sev, $LogData, $level) }
    function Get-CippException { param($Exception) }
    function Get-CIPPTable { param($TableName) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }

    . $FunctionPath
}

Describe 'Test-CIPPAccessTenant' {
    BeforeEach {
        $env:TenantID = '00000000-0000-0000-0000-00000000partner'

        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { @{ NormalizedError = 'stub error' } }
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'stub-table' } }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }

        # Skip the Exchange leg - it is identical for both tenant types and needs far more scaffolding.
        Mock -CommandName Test-CIPPStandardLicense -MockWith { $false }
        Mock -CommandName New-ExoRequest -MockWith { }
    }

    Context 'Direct tenants' {
        BeforeEach {
            $script:AllExpectedRoleIds = @(
                '9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3', 'fe930be7-5e62-47db-91af-98c3a49a38b1',
                '3a2c62db-5318-420d-8d74-23affee5d9d5', '29232cdf-9323-42fd-ade2-1d097af3e4de',
                '194ae4cb-b126-40b2-bd5b-6091b380977d', '892c5842-a9a6-463a-8041-72aa08ca3cf6',
                '7698a772-787b-4ac8-901f-60d6b08affd2', '69091246-20e8-4a56-aa4d-066075b2a7a8',
                'f28a1f50-f6e7-4571-818b-6a12f2af6b6c', '0526716b-113d-4c15-b2c8-68e3c22b9f80',
                'e8611ab8-c189-46e8-94e1-60213ab1f814', '7be44c8a-adaf-4e2a-84d6-ab2649e08a13',
                'b0f54661-2d74-4c50-afa3-1ec803f12efe', 'f2ef992c-3afb-46b9-b7cf-a126ee74c451',
                '8329153b-31d0-4727-b945-745eb3bc5f31'
            )

            Mock -CommandName Get-Tenants -MockWith {
                [pscustomobject]@{
                    customerId               = '11111111-1111-1111-1111-111111111111'
                    defaultDomainName        = 'direct.onmicrosoft.com'
                    displayName              = 'Direct Tenant'
                    delegatedPrivilegeStatus = 'directTenant'
                }
            }
            Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*/me?*' } -MockWith {
                [pscustomobject]@{
                    id                = 'service-account-id'
                    displayName       = 'CIPP Service Account'
                    userPrincipalName = 'cipp@direct.onmicrosoft.com'
                }
            }
            # Default: the service account holds every expected role directly.
            Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*transitiveMemberOf*' } -MockWith {
                $script:AllExpectedRoleIds | ForEach-Object {
                    [pscustomobject]@{ '@odata.type' = '#microsoft.graph.directoryRole'; roleTemplateId = $_ }
                }
            }
            Mock -CommandName New-GraphBulkRequest -MockWith { @() }
        }

        It 'reports the tenant as a Direct tenant' {
            $Result = Test-CIPPAccessTenant -Tenant 'direct.onmicrosoft.com'
            $Result.TenantType | Should -Be 'Direct'
        }

        It 'records the service account it authenticated as' {
            $Result = Test-CIPPAccessTenant -Tenant 'direct.onmicrosoft.com'
            $Result.ServiceAccount | Should -Be 'cipp@direct.onmicrosoft.com'
        }

        It 'does not enumerate partner GDAP role assignments' {
            $null = Test-CIPPAccessTenant -Tenant 'direct.onmicrosoft.com'
            Should -Invoke -CommandName New-GraphBulkRequest -Times 0 -Exactly
        }

        It 'reports the roles the service account holds and none missing' {
            $Result = Test-CIPPAccessTenant -Tenant 'direct.onmicrosoft.com'
            $Result.GraphStatus | Should -BeTrue
            @($Result.MissingRoles).Count | Should -Be 0
            @($Result.AssignedRoles).Count | Should -Be $script:AllExpectedRoleIds.Count
            $Result.AssignedRoles[0].Group | Should -Be 'cipp@direct.onmicrosoft.com'
            $Result.GraphTest | Should -Be 'Successfully connected to Graph'
        }

        It 'reports missing required roles when the service account lacks them' {
            Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*transitiveMemberOf*' } -MockWith {
                @([pscustomobject]@{
                        '@odata.type'  = '#microsoft.graph.directoryRole'
                        roleTemplateId = 'fe930be7-5e62-47db-91af-98c3a49a38b1' # User Administrator only
                    })
            }
            $Result = Test-CIPPAccessTenant -Tenant 'direct.onmicrosoft.com'
            @($Result.AssignedRoles).Count | Should -Be 1
            @($Result.MissingRoles).Name | Should -Contain 'Intune Administrator'
            $Result.GraphTest | Should -BeLike '*missing required roles*'
        }

        It 'treats Global Administrator as satisfying every expected role' {
            Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*transitiveMemberOf*' } -MockWith {
                @([pscustomobject]@{
                        '@odata.type'  = '#microsoft.graph.directoryRole'
                        roleTemplateId = '62e90394-69f5-4237-9190-012177145e10' # Global Administrator
                    })
            }
            $Result = Test-CIPPAccessTenant -Tenant 'direct.onmicrosoft.com'
            @($Result.MissingRoles).Count | Should -Be 0
            @($Result.AssignedRoles).Count | Should -Be $script:AllExpectedRoleIds.Count
            $Result.AssignedRoles[0].Group | Should -BeLike '*via Global Administrator*'
        }

        It 'flags only optional roles when just those are absent' {
            Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*transitiveMemberOf*' } -MockWith {
                $Required = $script:AllExpectedRoleIds | Select-Object -First 12
                $Required | ForEach-Object {
                    [pscustomobject]@{ '@odata.type' = '#microsoft.graph.directoryRole'; roleTemplateId = $_ }
                }
            }
            $Result = Test-CIPPAccessTenant -Tenant 'direct.onmicrosoft.com'
            @($Result.MissingRoles).Count | Should -Be 3
            $Result.GraphTest | Should -BeLike '*missing optional roles*'
        }

        It 'ignores group memberships when deriving roles' {
            Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*transitiveMemberOf*' } -MockWith {
                @(
                    [pscustomobject]@{ '@odata.type' = '#microsoft.graph.group'; id = 'some-group' }
                    [pscustomobject]@{ '@odata.type' = '#microsoft.graph.directoryRole'; roleTemplateId = 'fe930be7-5e62-47db-91af-98c3a49a38b1' }
                )
            }
            $Result = Test-CIPPAccessTenant -Tenant 'direct.onmicrosoft.com'
            @($Result.AssignedRoles).Count | Should -Be 1
        }

        It 'fails the Graph check when the tenant token is not usable' {
            Mock -CommandName New-GraphGetRequest -ParameterFilter { $uri -like '*/me?*' } -MockWith {
                throw 'invalid_grant'
            }
            $Result = Test-CIPPAccessTenant -Tenant 'direct.onmicrosoft.com'
            $Result.GraphStatus | Should -BeFalse
            $Result.GraphTest | Should -BeLike 'Failed to connect to Graph*'
        }
    }

    Context 'GDAP tenants' {
        BeforeEach {
            Mock -CommandName Get-Tenants -MockWith {
                [pscustomobject]@{
                    customerId               = '22222222-2222-2222-2222-222222222222'
                    defaultDomainName        = 'gdap.onmicrosoft.com'
                    displayName              = 'GDAP Tenant'
                    delegatedPrivilegeStatus = 'granularDelegatedAdminPrivileges'
                }
            }
            Mock -CommandName New-GraphBulkRequest -MockWith { @() }
            Mock -CommandName New-GraphGetRequest -MockWith { @() }
        }

        It 'reports the tenant as a GDAP tenant' {
            $Result = Test-CIPPAccessTenant -Tenant 'gdap.onmicrosoft.com'
            $Result.TenantType | Should -Be 'GDAP'
        }

        It 'still enumerates partner GDAP role assignments' {
            $null = Test-CIPPAccessTenant -Tenant 'gdap.onmicrosoft.com'
            Should -Invoke -CommandName New-GraphBulkRequest -Times 1 -Exactly
        }

        It 'still reports missing roles when the partner holds no role assignments' {
            $Result = Test-CIPPAccessTenant -Tenant 'gdap.onmicrosoft.com'
            @($Result.MissingRoles).Count | Should -BeGreaterThan 0
            $Result.GraphTest | Should -BeLike '*missing required GDAP roles*'
        }
    }
}

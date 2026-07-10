# Pester tests for Get-CIPPSharedMailboxAccountEnabledReport
# Verifies the cached Mailboxes + Users join, accountEnabled filtering, payload shape, and AllTenants fan-out

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $ReportPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPSharedMailboxAccountEnabledReport.ps1'

    # Minimal stubs so Mock has commands to replace during tests
    function Get-CIPPDbItem { param($TenantFilter, $Type) }
    function Get-Tenants { param([switch]$IncludeErrors) }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }

    . $ReportPath

    function New-DbItem {
        param($PartitionKey, $RowKey, $Data, $Timestamp)
        [pscustomobject]@{
            PartitionKey = $PartitionKey
            RowKey       = $RowKey
            Timestamp    = $Timestamp
            Data         = ($Data | ConvertTo-Json -Depth 5 -Compress)
        }
    }
}

Describe 'Get-CIPPSharedMailboxAccountEnabledReport' {
    BeforeEach {
        $script:Tenant = 'contoso.onmicrosoft.com'

        $script:SharedMailbox = @{ UPN = 'shared@contoso.com'; recipientTypeDetails = 'SharedMailbox' }
        $script:RegularMailbox = @{ UPN = 'user@contoso.com'; recipientTypeDetails = 'UserMailbox' }

        $script:EnabledUser = @{
            userPrincipalName     = 'shared@contoso.com'
            displayName           = 'Shared Mailbox'
            givenName             = 'Shared'
            surname               = 'Mailbox'
            accountEnabled        = $true
            assignedLicenses      = @(@{ skuId = 'sku-1' })
            id                    = 'user-id-shared'
            onPremisesSyncEnabled = $false
        }
        $script:RegularUser = @{
            userPrincipalName     = 'user@contoso.com'
            displayName           = 'Regular User'
            accountEnabled        = $true
            id                    = 'user-id-regular'
            onPremisesSyncEnabled = $false
        }

        $script:Now = Get-Date

        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-Tenants -MockWith { @([pscustomobject]@{ defaultDomainName = 'contoso.onmicrosoft.com' }) }
    }

    It 'joins a shared mailbox to its user and returns the live payload shape' {
        Mock -CommandName Get-CIPPDbItem -ParameterFilter { $Type -eq 'Mailboxes' } -MockWith {
            @(
                New-DbItem -PartitionKey $script:Tenant -RowKey 'Mailboxes-Count' -Data @{ Count = 2 } -Timestamp $script:Now
                New-DbItem -PartitionKey $script:Tenant -RowKey '1' -Data $script:SharedMailbox -Timestamp $script:Now
                New-DbItem -PartitionKey $script:Tenant -RowKey '2' -Data $script:RegularMailbox -Timestamp $script:Now
            )
        }
        Mock -CommandName Get-CIPPDbItem -ParameterFilter { $Type -eq 'Users' } -MockWith {
            @(
                New-DbItem -PartitionKey $script:Tenant -RowKey 'Users-Count' -Data @{ Count = 2 } -Timestamp $script:Now
                New-DbItem -PartitionKey $script:Tenant -RowKey 'u1' -Data $script:EnabledUser -Timestamp $script:Now
                New-DbItem -PartitionKey $script:Tenant -RowKey 'u2' -Data $script:RegularUser -Timestamp $script:Now
            )
        }

        $Result = Get-CIPPSharedMailboxAccountEnabledReport -TenantFilter $script:Tenant

        @($Result).Count | Should -Be 1
        $Result[0].UserPrincipalName | Should -Be 'shared@contoso.com'
        $Result[0].id | Should -Be 'user-id-shared'
        $Result[0].accountEnabled | Should -BeTrue
        $Result[0].onPremisesSyncEnabled | Should -BeFalse
        $Result[0].CacheTimestamp | Should -Not -BeNullOrEmpty
        # Must not leak the regular (non-shared) mailbox
        $Result.UserPrincipalName | Should -Not -Contain 'user@contoso.com'
    }

    It 'excludes shared mailboxes whose user account is disabled' {
        $script:EnabledUser.accountEnabled = $false
        Mock -CommandName Get-CIPPDbItem -ParameterFilter { $Type -eq 'Mailboxes' } -MockWith {
            @(
                New-DbItem -PartitionKey $script:Tenant -RowKey 'Mailboxes-Count' -Data @{ Count = 1 } -Timestamp $script:Now
                New-DbItem -PartitionKey $script:Tenant -RowKey '1' -Data $script:SharedMailbox -Timestamp $script:Now
            )
        }
        Mock -CommandName Get-CIPPDbItem -ParameterFilter { $Type -eq 'Users' } -MockWith {
            @(New-DbItem -PartitionKey $script:Tenant -RowKey 'u1' -Data $script:EnabledUser -Timestamp $script:Now)
        }

        $Result = Get-CIPPSharedMailboxAccountEnabledReport -TenantFilter $script:Tenant

        @($Result).Count | Should -Be 0
    }

    It 'returns an empty result (no throw) when the cache holds no enabled shared mailboxes' {
        Mock -CommandName Get-CIPPDbItem -ParameterFilter { $Type -eq 'Mailboxes' } -MockWith {
            @(
                New-DbItem -PartitionKey $script:Tenant -RowKey 'Mailboxes-Count' -Data @{ Count = 1 } -Timestamp $script:Now
                New-DbItem -PartitionKey $script:Tenant -RowKey '1' -Data $script:RegularMailbox -Timestamp $script:Now
            )
        }
        Mock -CommandName Get-CIPPDbItem -ParameterFilter { $Type -eq 'Users' } -MockWith {
            @(New-DbItem -PartitionKey $script:Tenant -RowKey 'u2' -Data $script:RegularUser -Timestamp $script:Now)
        }

        { Get-CIPPSharedMailboxAccountEnabledReport -TenantFilter $script:Tenant } | Should -Not -Throw
        @(Get-CIPPSharedMailboxAccountEnabledReport -TenantFilter $script:Tenant).Count | Should -Be 0
    }

    It 'throws when no mailbox data is cached' {
        Mock -CommandName Get-CIPPDbItem -ParameterFilter { $Type -eq 'Mailboxes' } -MockWith { @() }
        Mock -CommandName Get-CIPPDbItem -ParameterFilter { $Type -eq 'Users' } -MockWith { @() }

        { Get-CIPPSharedMailboxAccountEnabledReport -TenantFilter $script:Tenant } | Should -Throw '*Sync the report data first*'
    }

    It 'adds a Tenant column for AllTenants' {
        Mock -CommandName Get-CIPPDbItem -ParameterFilter { $Type -eq 'Mailboxes' } -MockWith {
            @(
                New-DbItem -PartitionKey $script:Tenant -RowKey 'Mailboxes-Count' -Data @{ Count = 1 } -Timestamp $script:Now
                New-DbItem -PartitionKey $script:Tenant -RowKey '1' -Data $script:SharedMailbox -Timestamp $script:Now
            )
        }
        Mock -CommandName Get-CIPPDbItem -ParameterFilter { $Type -eq 'Users' } -MockWith {
            @(New-DbItem -PartitionKey $script:Tenant -RowKey 'u1' -Data $script:EnabledUser -Timestamp $script:Now)
        }

        $Result = Get-CIPPSharedMailboxAccountEnabledReport -TenantFilter 'AllTenants'

        @($Result).Count | Should -Be 1
        $Result[0].Tenant | Should -Be 'contoso.onmicrosoft.com'
        $Result[0].UserPrincipalName | Should -Be 'shared@contoso.com'
    }
}

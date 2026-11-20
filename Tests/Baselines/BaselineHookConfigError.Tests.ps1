# A hook that cannot grade because of the baseline's own settings returns ConfigError, so the engine does not re-collect.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Hooks = Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/PrepareHooks'

    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Get-CIPPBaselineCacheRows { param($TenantFilter, $Type) }
    function Test-CIPPBaselineCacheCollected { param($TenantFilter, $Type) $true }

    foreach ($Name in 'AuthenticationMethods', 'DefenderExclusionPolicy', 'SecureScoreRemediation', 'AutoAddProxy') {
        . (Join-Path $Hooks "Get-CIPPBaseline$($Name)State.ps1")
    }
    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Prepare hooks with nothing configured' {
    BeforeEach {
        Mock Get-CIPPBaselineCacheRows {
            switch ($Type) {
                'AuthenticationMethodsPolicy' { [PSCustomObject]@{ id = 'authenticationMethodsPolicy'; authenticationMethodConfigurations = @() } }
                'IntuneConfigurationPolicies' { [PSCustomObject]@{ id = 'p1'; name = 'Another policy' } }
                'SecureScoreControlProfiles' { [PSCustomObject]@{ id = 'MFARegistrationV2'; controlStateUpdates = @() } }
            }
        }
    }

    It '<Name> reports a configuration problem so the engine does not re-collect' -ForEach @(
        @{ Name = 'AuthenticationMethods'; Variables = [PSCustomObject]@{} }
        @{ Name = 'DefenderExclusionPolicy'; Variables = [PSCustomObject]@{ excludedExtensions = ''; excludedPaths = ''; excludedProcesses = '' } }
        @{ Name = 'SecureScoreRemediation'; Variables = [PSCustomObject]@{} }
    ) {
        $Prepared = & "Get-CIPPBaseline$($Name)State" -Item ([PSCustomObject]@{ Variables = $Variables }) -TenantFilter $script:Tenant

        $Prepared.Current | Should -BeNullOrEmpty
        $Prepared.ConfigError | Should -BeTrue
        $Prepared.NoDataReason | Should -BeNullOrEmpty
    }

    It 'AuthenticationMethods still returns no data without ConfigError when the cache is empty' {
        Mock Get-CIPPBaselineCacheRows {}

        $Prepared = Get-CIPPBaselineAuthenticationMethodsState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{ SMSEnabled = $false } }) -TenantFilter $script:Tenant

        $Prepared.Current | Should -BeNullOrEmpty
        $Prepared.ConfigError | Should -BeNullOrEmpty
    }
}

Describe 'AutoAddProxy prepare hook' {
    BeforeEach {
        Mock New-CIPPDbRequest {
            @(
                [PSCustomObject]@{ UPN = 'ann@contoso.onmicrosoft.com'; primarySmtpAddress = 'Ann@Contoso.com'; AdditionalEmailAddresses = 'ann@contoso.onmicrosoft.com, ann@FABRIKAM.com' }
                [PSCustomObject]@{ UPN = 'bob@contoso.onmicrosoft.com'; primarySmtpAddress = 'bob@contoso.com'; AdditionalEmailAddresses = '' }
                [PSCustomObject]@{ UPN = ''; primarySmtpAddress = 'nobody@contoso.com' }
            )
        }
        Mock Get-CIPPBaselineCacheRows { @([PSCustomObject]@{ DomainName = 'contoso.com' }, [PSCustomObject]@{ DomainName = 'fabrikam.com' }, [PSCustomObject]@{ DomainName = 'contoso.onmicrosoft.com' }) }
    }

    It 'lists each mailbox and accepted domain pair with no address, matching domains case-insensitively' {
        $Prepared = Get-CIPPBaselineAutoAddProxyState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{} }) -TenantFilter $script:Tenant

        $Prepared.Current.offenders | Should -Be @('bob@contoso.onmicrosoft.com -> contoso.onmicrosoft.com', 'bob@contoso.onmicrosoft.com -> fabrikam.com')
        $Prepared.Current.targets.alias | Should -Be @('smtp:bob@fabrikam.com', 'smtp:bob@contoso.onmicrosoft.com')
        $Prepared.Current.targets.id | Should -Be @('bob@contoso.onmicrosoft.com', 'bob@contoso.onmicrosoft.com')
    }
}

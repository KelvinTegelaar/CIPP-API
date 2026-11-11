# Get-AuthorisedRequest skips the tenant check only for partner-level URLs matched on the parsed host and path,
# and a tenant-restricted caller never falls back to the partner tenant.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-Tenants { param([switch]$IncludeErrors, $TenantFilter) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-AuthorisedRequest.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Initialize-CippRequestContext.ps1')

    $script:SavedTenantID = $env:TenantID
    $env:TenantID = 'partner-tenant-id'
    $script:InScope = '11111111-1111-1111-1111-111111111111'
    $script:OutOfScope = '99999999-9999-9999-9999-999999999999'
}

AfterAll {
    $env:TenantID = $script:SavedTenantID
}

Describe 'Get-AuthorisedRequest URI exemptions' {
    BeforeEach {
        Initialize-CippRequestContext
        Mock Get-Tenants {
            switch ($TenantFilter) {
                'contoso.com' { [pscustomobject]@{ defaultDomainName = 'contoso.com'; Excluded = $false } }
                'partner-tenant-id' { [pscustomobject]@{ defaultDomainName = 'partner.com'; Excluded = $false } }
            }
        }
    }

    It 'allows the partner-level URL <Uri> without a tenant lookup' -ForEach @(
        @{ Uri = 'https://api.partnercenter.microsoft.com/v1/customers/11111111-1111-1111-1111-111111111111/DeviceBatches' }
        @{ Uri = 'https://api.partnercenter.microsoft.com/v1/customers/11111111-1111-1111-1111-111111111111' }
        @{ Uri = 'https://api.partnercenter.microsoft.com/v1//customers/11111111-1111-1111-1111-111111111111/batchJobStatus/job-1' }
        @{ Uri = 'https://api.partnercenter.microsoft.com/v1/customers/relationshiprequests?dualRoleIndirectRelationship=false' }
        @{ Uri = 'https://graph.microsoft.com/beta/contracts?$top=999' }
        @{ Uri = 'https://graph.microsoft.com/v1.0/me/sendMail' }
        @{ Uri = "https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships?`$filter=status eq 'active'" }
        @{ Uri = 'https://graph.microsoft.com/v1.0/tenantRelationships/delegatedAdminRelationships/abc-123/requests' }
        @{ Uri = 'https://graph.microsoft.com/beta/tenantRelationships/managedTenants/managedDeviceCompliances' }
        @{ Uri = 'https://graph.microsoft.com/beta/security/partner/securityAlerts' }
        @{ Uri = 'https://graph.microsoft.com/beta/organization' }
        @{ Uri = 'https://graph.microsoft.com/v1.0/organization?$select=displayName' }
    ) {
        Get-AuthorisedRequest -Uri $Uri -TenantID 'unknown.com' | Should -BeTrue
        Should -Invoke Get-Tenants -Times 0 -Exactly
    }

    It 'refuses <Name> for a tenant outside the list' -ForEach @(
        @{ Name = 'a fragment'; Uri = 'https://graph.microsoft.com/beta/users/x#/customers/' }
        @{ Name = 'a fragment hiding an organization path'; Uri = 'https://graph.microsoft.com/beta/users/x#/organization' }
        @{ Name = 'a dot segment'; Uri = 'https://graph.microsoft.com/beta/users/x/../../beta/tenantRelationships/delegatedAdminRelationships' }
        @{ Name = 'an encoded dot segment'; Uri = 'https://graph.microsoft.com/beta/users/x/%2e%2e/%2E%2E/beta/organization' }
        @{ Name = 'a backslash'; Uri = 'https://graph.microsoft.com/beta/users/x\..\/customers/y' }
        @{ Name = 'a lookalike host'; Uri = 'https://graph.microsoft.com.example.net/beta/tenantRelationships/x' }
        @{ Name = 'another host with a customers path'; Uri = 'https://example.net/v1/customers/abc' }
        @{ Name = 'a customers segment deeper in a Graph path'; Uri = 'https://graph.microsoft.com/beta/users/customers/x' }
        @{ Name = 'an organization segment deeper in a Graph path'; Uri = 'https://graph.microsoft.com/beta/users/x/organization' }
        @{ Name = 'a relative URI'; Uri = '/beta/organization' }
    ) {
        Get-AuthorisedRequest -Uri $Uri -TenantID 'unknown.com' | Should -BeFalse
    }

    It 'still checks the tenant for an ordinary URL' {
        Get-AuthorisedRequest -Uri 'https://graph.microsoft.com/beta/users' -TenantID 'contoso.com' | Should -BeTrue
        Get-AuthorisedRequest -Uri 'https://graph.microsoft.com/beta/users' -TenantID 'unknown.com' | Should -BeFalse
        Get-AuthorisedRequest -TenantID 'contoso.com' | Should -BeTrue
    }
}

Describe 'Get-AuthorisedRequest without a tenant' {
    BeforeEach {
        Initialize-CippRequestContext
        Mock Get-Tenants {
            switch ($TenantFilter) {
                'partner-tenant-id' { [pscustomobject]@{ defaultDomainName = 'partner.com'; Excluded = $false } }
            }
        }
    }

    It 'falls back to the partner tenant for an unrestricted caller' {
        Get-AuthorisedRequest -Uri 'https://graph.microsoft.com/beta/users' | Should -BeTrue
        Should -Invoke Get-Tenants -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'partner-tenant-id' }
        Get-AuthorisedRequest -Uri 'https://graph.microsoft.com/beta/organization' | Should -BeTrue
    }

    Context 'restricted caller' {
        BeforeEach {
            $script:CippAllowedTenantsStorage.Value = @($script:InScope)
        }

        It 'refuses <Uri>' -ForEach @(
            @{ Uri = 'https://graph.microsoft.com/beta/users' }
            @{ Uri = 'https://graph.microsoft.com/beta/organization' }
            @{ Uri = 'https://graph.microsoft.com/beta/contracts?$top=999' }
            @{ Uri = 'https://graph.microsoft.com/v1.0/me/sendMail' }
            @{ Uri = 'https://graph.microsoft.com/beta/tenantRelationships/delegatedAdminRelationships' }
            @{ Uri = 'https://graph.microsoft.com/beta/security/partner/securityAlerts' }
            @{ Uri = 'https://api.partnercenter.microsoft.com/v1/customers/relationshiprequests' }
            @{ Uri = 'https://api.partnercenter.microsoft.com/v1/customers/99999999-9999-9999-9999-999999999999/DeviceBatches' }
            @{ Uri = 'https://api.partnercenter.microsoft.com/v1/customers//DeviceBatches' }
            @{ Uri = '' }
        ) {
            Get-AuthorisedRequest -Uri $Uri | Should -BeFalse
            Should -Invoke Get-Tenants -Times 0 -Exactly
        }

        It 'allows <Uri>' -ForEach @(
            @{ Uri = 'https://graph.microsoft.com/beta/tenantRelationships/managedTenants/managedDeviceCompliances' }
            @{ Uri = 'https://api.partnercenter.microsoft.com/v1/customers/11111111-1111-1111-1111-111111111111/DeviceBatches' }
            @{ Uri = 'https://api.partnercenter.microsoft.com/v1//customers/11111111-1111-1111-1111-111111111111/batchJobStatus/job-1' }
        ) {
            Get-AuthorisedRequest -Uri $Uri | Should -BeTrue
        }

        It 'still allows an explicit tenant in scope' {
            Mock Get-Tenants { [pscustomobject]@{ defaultDomainName = 'contoso.com'; customerId = $script:InScope; Excluded = $false } } -ParameterFilter { $TenantFilter -eq 'contoso.com' }
            Get-AuthorisedRequest -Uri 'https://graph.microsoft.com/beta/users' -TenantID 'contoso.com' | Should -BeTrue
        }
    }
}

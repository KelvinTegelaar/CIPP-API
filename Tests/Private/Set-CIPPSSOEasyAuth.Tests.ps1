# Pester tests for Set-CIPPSSOEasyAuth
# Focused on WEBSITE_AUTH_AAD_ALLOWED_TENANTS: restricted multi-tenant mode writes this tenant plus the
# listed ones, a call that does not pass a list (warmup reconcile) keeps the current one, and single
# tenant or an empty list clears it.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Set-CIPPSSOEasyAuth.ps1')

    function Write-LogMessage { param($API, $message, $sev) }
    function Get-CippKeyVaultName { }

    $script:HomeTenant = '11111111-1111-1111-1111-111111111111'
    $script:Partner = '22222222-2222-2222-2222-222222222222'
    $script:EnvNames = @('WEBSITE_SITE_NAME', 'WEBSITE_RESOURCE_GROUP', 'WEBSITE_OWNER_NAME', 'IDENTITY_ENDPOINT', 'IDENTITY_HEADER', 'WEBSITE_AUTH_V2_CONFIG_JSON', 'CRAFT_ROOT')
    $script:SavedEnv = @{}
    foreach ($Name in $EnvNames) { $SavedEnv[$Name] = [Environment]::GetEnvironmentVariable($Name) }
}

AfterAll {
    foreach ($Name in $EnvNames) { [Environment]::SetEnvironmentVariable($Name, $SavedEnv[$Name]) }
}

Describe 'Set-CIPPSSOEasyAuth allowed tenants' {
    BeforeEach {
        [Environment]::SetEnvironmentVariable('WEBSITE_SITE_NAME', 'cipp-test')
        [Environment]::SetEnvironmentVariable('WEBSITE_RESOURCE_GROUP', 'rg')
        [Environment]::SetEnvironmentVariable('WEBSITE_OWNER_NAME', 'sub+rg-region')
        [Environment]::SetEnvironmentVariable('IDENTITY_ENDPOINT', 'http://identity')
        [Environment]::SetEnvironmentVariable('IDENTITY_HEADER', 'h')
        [Environment]::SetEnvironmentVariable('WEBSITE_AUTH_V2_CONFIG_JSON', $null)
        [Environment]::SetEnvironmentVariable('CRAFT_ROOT', $null)

        $script:Written = $null
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Invoke-RestMethod -MockWith { [pscustomobject]@{ access_token = 't' } } -ParameterFilter { $Uri -like 'http://identity*' }
        Mock -CommandName Invoke-RestMethod -MockWith {
            [pscustomobject]@{ properties = [pscustomobject]@{ WEBSITE_AUTH_AAD_ALLOWED_TENANTS = "$HomeTenant,33333333-3333-3333-3333-333333333333"; OTHER = 'x' } }
        } -ParameterFilter { $Uri -like '*/config/appsettings/list*' }
        Mock -CommandName Invoke-RestMethod -MockWith { $script:Written = ($Body | ConvertFrom-Json).properties } -ParameterFilter { $Method -eq 'Put' -and $Uri -like '*/config/appsettings*' }
        Mock -CommandName Invoke-RestMethod -MockWith { } -ParameterFilter { $Uri -like '*/config/authsettingsV2*' }
    }

    It 'restricts a multi-tenant app to this tenant plus the listed ones' {
        $null = Set-CIPPSSOEasyAuth -AppId 'app' -MultiTenant $true -TenantId $HomeTenant -AllowedTenants @($Partner.ToUpper(), $HomeTenant, '')

        $Written.WEBSITE_AUTH_AAD_ALLOWED_TENANTS | Should -Be "$HomeTenant,$Partner"
        $Written.OTHER | Should -Be 'x'
    }

    It 'keeps the current list when none is passed' {
        $null = Set-CIPPSSOEasyAuth -AppId 'app' -MultiTenant $true -TenantId $HomeTenant

        $Written.WEBSITE_AUTH_AAD_ALLOWED_TENANTS | Should -Be "$HomeTenant,33333333-3333-3333-3333-333333333333"
    }

    It 'opens a multi-tenant app to any tenant when the list is empty' {
        $null = Set-CIPPSSOEasyAuth -AppId 'app' -MultiTenant $true -TenantId $HomeTenant -AllowedTenants @()

        $Written.OTHER | Should -Be 'x'
        $Written.PSObject.Properties.Name | Should -Not -Contain 'WEBSITE_AUTH_AAD_ALLOWED_TENANTS'
    }

    It 'clears the list for a single-tenant app, whose issuer restricts it' {
        $null = Set-CIPPSSOEasyAuth -AppId 'app' -MultiTenant $false -TenantId $HomeTenant -AllowedTenants @($Partner)

        $Written.OTHER | Should -Be 'x'
        $Written.PSObject.Properties.Name | Should -Not -Contain 'WEBSITE_AUTH_AAD_ALLOWED_TENANTS'
    }
}

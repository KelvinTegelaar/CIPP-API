BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    if (-not ('CIPP.CIPPTokenCache' -as [type])) {
        Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    }

    function Get-CIPPAuthentication { $true }
    function Get-CippTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Update-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Invoke-CIPPRestMethod { param($Method, $Uri, $Body, $ContentType) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-GraphToken.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Clear-CippTokenCache.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
}

Describe 'Get-GraphToken failure cache' {
    BeforeEach {
        $script:SavedEnv = @{}
        foreach ($Name in 'CertificateAuthMode', 'ApplicationID', 'ApplicationSecret', 'TenantID', 'RefreshToken', 'SetFromProfile') {
            $script:SavedEnv[$Name] = [Environment]::GetEnvironmentVariable($Name)
        }
        Remove-Item env:CertificateAuthMode -ErrorAction SilentlyContinue
        $env:ApplicationID = 'sam-app-id'
        $env:ApplicationSecret = 'sam-secret'
        $env:TenantID = '11111111-2222-3333-4444-555555555555'
        $env:RefreshToken = 'sam-refresh-token'
        $env:SetFromProfile = 'true'
        $null = [CIPP.CIPPTokenCache]::Clear()

        Mock Get-CippTable { @{} }
        Mock Get-CIPPAzDataTableEntity { $null }
        Mock Update-AzDataTableEntity {}
        Mock Invoke-CIPPRestMethod { throw 'invalid_grant:AADSTS50079: Due to a configuration change made by your administrator, you must enroll in multi-factor authentication.' }
    }

    AfterEach {
        $null = [CIPP.CIPPTokenCache]::Clear()
        foreach ($Name in $script:SavedEnv.Keys) {
            if ($null -eq $script:SavedEnv[$Name]) {
                Remove-Item "env:$Name" -ErrorAction SilentlyContinue
            } else {
                Set-Item "env:$Name" -Value $script:SavedEnv[$Name]
            }
        }
    }

    It 'fails fast with the same message after an admin-fixable error' {
        { Get-GraphToken -tenantid 'contoso.com' } | Should -Throw '*AADSTS50079*'
        { Get-GraphToken -tenantid 'contoso.com' } | Should -Throw '*AADSTS50079*'

        Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly
        Should -Invoke Update-AzDataTableEntity -Times 0 -Exactly
    }

    It 'does not cache a transient error' {
        Mock Invoke-CIPPRestMethod { throw 'temporarily_unavailable:AADSTS90033: A transient error has occurred.' }

        { Get-GraphToken -tenantid 'contoso.com' } | Should -Throw '*AADSTS90033*'
        { Get-GraphToken -tenantid 'contoso.com' } | Should -Throw '*AADSTS90033*'

        Should -Invoke Invoke-CIPPRestMethod -Times 2 -Exactly
    }

    It 'keeps app-only and other scopes usable when the delegated Graph token failed' {
        { Get-GraphToken -tenantid 'contoso.com' } | Should -Throw
        Mock Invoke-CIPPRestMethod { @{ access_token = 'ok-token'; expires_in = 3600 } }

        (Get-GraphToken -tenantid 'contoso.com' -AsApp $true).Authorization | Should -Be 'Bearer ok-token'
        (Get-GraphToken -tenantid 'contoso.com' -scope 'https://outlook.office365.com/.default').Authorization | Should -Be 'Bearer ok-token'
    }

    It 'retries when the caller skips the cache' {
        { Get-GraphToken -tenantid 'contoso.com' } | Should -Throw
        { Get-GraphToken -tenantid 'contoso.com' -SkipCache $true } | Should -Throw

        Should -Invoke Invoke-CIPPRestMethod -Times 2 -Exactly
    }

    It 'is cleared by a tenant clear that names the GUID when the failure was keyed by domain' {
        Mock Get-CIPPAzDataTableEntity -ParameterFilter { $Filter -like "*customerId eq 'aaaaaaaa-0000-0000-0000-000000000001'*" } {
            [pscustomobject]@{ customerId = 'aaaaaaaa-0000-0000-0000-000000000001'; defaultDomainName = 'contoso.com'; initialDomainName = 'contoso.onmicrosoft.com' }
        }
        { Get-GraphToken -tenantid 'contoso.com' } | Should -Throw

        $null = Clear-CippTokenCache -TenantFilter 'aaaaaaaa-0000-0000-0000-000000000001'
        Mock Invoke-CIPPRestMethod { @{ access_token = 'fixed-token'; expires_in = 3600 } }

        (Get-GraphToken -tenantid 'contoso.com').Authorization | Should -Be 'Bearer fixed-token'
    }
}

# Pester tests for Get-CIPPAlertGlobalAdminAllowList
# Verifies prefix-based allow list handling and alert emission

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AlertPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Alerts/Get-CIPPAlertGlobalAdminAllowList.ps1'

    # Provide minimal stubs so Mock has commands to replace during tests
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }
    function Write-AlertMessage { param($tenant, $message) }

    . $AlertPath
}

Describe 'Get-CIPPAlertGlobalAdminAllowList' {
    BeforeEach {
        $script:CapturedData = $null
        $script:CapturedTenant = $null

        Mock -CommandName New-GraphGetRequest -MockWith {
            @(
                [pscustomobject]@{
                    '@odata.type'       = '#microsoft.graph.user'
                    displayName         = 'Allowed Admin'
                    userPrincipalName   = 'breakglass@contoso.com'
                    id                  = 'id-allowed'
                },
                [pscustomobject]@{
                    '@odata.type'       = '#microsoft.graph.user'
                    displayName         = 'Unapproved Admin'
                    userPrincipalName   = 'otheradmin@contoso.com'
                    id                  = 'id-unapproved'
                }
            )
        }

        Mock -CommandName Write-AlertTrace -MockWith {
            param($cmdletName, $tenantFilter, $data)
            $script:CapturedData = $data
            $script:CapturedTenant = $tenantFilter
        }

        Mock -CommandName Write-AlertMessage {}
    }

    It 'emits per-admin alerts when AlertEachAdmin is true' {
        $allowInput = @{ ApprovedGlobalAdmins = 'breakglass'; AlertEachAdmin = $true }

        Get-CIPPAlertGlobalAdminAllowList -TenantFilter 'contoso.onmicrosoft.com' -InputValue $allowInput

        $CapturedData | Should -Not -BeNullOrEmpty
        $CapturedData.UserPrincipalName | Should -Contain 'otheradmin@contoso.com'
        $CapturedData.UserPrincipalName | Should -Not -Contain 'breakglass@contoso.com'
        $CapturedTenant | Should -Be 'contoso.onmicrosoft.com'
    }

    It 'emits single aggregated alert when AlertEachAdmin is false (default)' {
        Get-CIPPAlertGlobalAdminAllowList -TenantFilter 'contoso.onmicrosoft.com' -InputValue 'breakglass'

        $CapturedData | Should -Not -BeNullOrEmpty
        $CapturedData.Count | Should -Be 1
        $CapturedData[0].NonCompliantUsers | Should -Contain 'otheradmin@contoso.com'
        $CapturedData[0].NonCompliantUsers | Should -Not -Contain 'breakglass@contoso.com'
    }

    It 'suppresses alert when UPN prefix is approved (comma separated list)' {
        $allowInput = @{ ApprovedGlobalAdmins = 'breakglass,otheradmin'; AlertEachAdmin = $true }
        Get-CIPPAlertGlobalAdminAllowList -TenantFilter 'contoso.onmicrosoft.com' -InputValue $allowInput

        $CapturedData | Should -BeNullOrEmpty
    }

    It 'accepts ApprovedGlobalAdmins property when provided as hashtable' {
        $allowInput = @{ ApprovedGlobalAdmins = 'breakglass,otheradmin' }
        Get-CIPPAlertGlobalAdminAllowList -TenantFilter 'contoso.onmicrosoft.com' -InputValue $allowInput

        $CapturedData | Should -BeNullOrEmpty
    }
}

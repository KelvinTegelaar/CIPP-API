# Pester tests for Set-CIPPRequirePasswordChange.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPRequirePasswordChange.ps1'
    if (-not (Test-Path $FunctionPath)) { throw "Could not locate Set-CIPPRequirePasswordChange.ps1 at $FunctionPath" }

    function New-GraphGetRequest { param($uri, $tenantid, $noPagination, $verbose) }
    function New-GraphPostRequest { param($uri, $tenantid, $type, $body, $verbose) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    . $FunctionPath
}

Describe 'Set-CIPPRequirePasswordChange' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippException -MockWith { @{ NormalizedError = 'graph failed' } }
    }

    It 'PATCHes forceChangePasswordNextSignIn for cloud users' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{
                onPremisesSyncEnabled = $false
                displayName           = 'Ada Lovelace'
                userPrincipalName     = 'ada@contoso.com'
            }
        }
        Mock -CommandName New-GraphPostRequest -MockWith { }

        $Result = Set-CIPPRequirePasswordChange -UserID 'user-guid' -TenantFilter 'contoso.com' -ForceChangePasswordNextSignIn $true

        $Result | Should -Match 'required'
        $Result | Should -Match 'ada@contoso.com'
        Should -Invoke New-GraphPostRequest -Times 1 -ParameterFilter {
            $type -eq 'PATCH' -and $body -match 'forceChangePasswordNextSignIn'
        }
    }

    It 'can clear the must-change flag' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{
                onPremisesSyncEnabled = $false
                displayName           = 'Ada Lovelace'
                userPrincipalName     = 'ada@contoso.com'
            }
        }
        $script:CapturedBody = $null
        Mock -CommandName New-GraphPostRequest -MockWith { $script:CapturedBody = $body }

        $Result = Set-CIPPRequirePasswordChange -UserID 'user-guid' -TenantFilter 'contoso.com' -ForceChangePasswordNextSignIn $false

        $Result | Should -Match 'not required'
        $script:CapturedBody | Should -Match '"forceChangePasswordNextSignIn":false'
    }

    It 'rejects directory-synced users without PATCHing' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{
                onPremisesSyncEnabled = $true
                displayName           = 'Synced User'
                userPrincipalName     = 'synced@contoso.com'
            }
        }
        Mock -CommandName New-GraphPostRequest -MockWith { }

        { Set-CIPPRequirePasswordChange -UserID 'synced-guid' -TenantFilter 'contoso.com' } |
            Should -Throw -ExpectedMessage '*directory synced*'

        Should -Invoke New-GraphPostRequest -Times 0
    }
}

# The AppPermissions table only records what CIPP asked for. When the CIPP service account cannot grant
# those permissions in the partner tenant, the tokens show the gap, and the check reports it as a warning.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPAccessPermissions.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Read-JwtAccessDetails.ps1')

    function Write-LogMessage { param($Headers, $API, $tenant, $message, $Sev, $LogData) }
    function Write-AlertMessage { param($tenant, $tenantId, $message) }
    function Get-CIPPAuthentication {}
    function Get-GraphToken { param($returnRefresh, $SkipCache, $AsApp) }
    function Get-CippSamPermissions {}
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function New-GraphGetRequest { param($uri, $tenantid, $NoAuthCheck, $noPagination, $AsApp) @() }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) @() }
    function Get-CippTable { param($tablename) @{ Context = $tablename } }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }

    function script:New-TestJwt {
        param([hashtable]$Claims)
        $Payload = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($Claims | ConvertTo-Json -Compress))).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        "eyJhbGciOiJub25lIn0.$Payload.sig"
    }

    $script:SavedEnv = @{}
    foreach ($Name in 'MSI_SECRET', 'AzureWebJobsStorage', 'NonLocalHostAzurite', 'ApplicationSecret', 'ApplicationID', 'TenantID') {
        $script:SavedEnv[$Name] = [Environment]::GetEnvironmentVariable($Name)
        [Environment]::SetEnvironmentVariable($Name, $null)
    }
}

AfterAll {
    foreach ($Name in $script:SavedEnv.Keys) { [Environment]::SetEnvironmentVariable($Name, $script:SavedEnv[$Name]) }
}

Describe 'Test-CIPPAccessPermissions token grant comparison' {
    BeforeEach {
        Mock -CommandName Get-CippSamPermissions -MockWith {
            [pscustomobject]@{
                Timestamp          = [datetime]::UtcNow
                MissingPermissions = [pscustomobject]@{}
                Permissions        = [pscustomobject]@{
                    '00000003-0000-0000-c000-000000000000' = [pscustomobject]@{
                        applicationPermissions = @(
                            [pscustomobject]@{ id = 'a1'; value = 'Application.ReadWrite.All' }
                            [pscustomobject]@{ id = 'a2'; value = 'Directory.Read.All' }
                        )
                        delegatedPermissions   = @(
                            [pscustomobject]@{ id = 'd1'; value = 'Directory.AccessAsUser.All' }
                            [pscustomobject]@{ id = 'd2'; value = 'offline_access' }
                        )
                    }
                }
            }
        }
    }

    It 'warns and lists the permissions missing from the tokens without failing the check' {
        Mock -CommandName Get-GraphToken -MockWith {
            param($returnRefresh, $SkipCache, $AsApp)
            if ($AsApp) {
                @{ access_token = New-TestJwt @{ appid = 'sam'; roles = @('Directory.Read.All') } }
            } else {
                @{ access_token = New-TestJwt @{ appid = 'sam'; name = 'CIPP Service'; amr = @('mfa'); scp = 'User.Read' } }
            }
        }

        $Result = Test-CIPPAccessPermissions -TenantFilter 'partner'

        $Result.WarningMessages.Count | Should -Be 2
        $Result.UngrantedPermissions.Type | Should -Be @('Application', 'Delegated')
        $Result.UngrantedPermissions.Permission | Should -Be @('Application.ReadWrite.All', 'Directory.AccessAsUser.All')
        $Result.Links.Href | Should -Contain 'https://docs.cipp.app/user-documentation/cipp/settings/permissions#permissions-not-granted-in-your-tenant'
        $Result.Success | Should -BeTrue
    }

    It 'reports both rows as granted when the tokens carry every permission' {
        Mock -CommandName Get-GraphToken -MockWith {
            param($returnRefresh, $SkipCache, $AsApp)
            if ($AsApp) {
                @{ access_token = New-TestJwt @{ appid = 'sam'; roles = @('Application.ReadWrite.All', 'Directory.Read.All') } }
            } else {
                @{ access_token = New-TestJwt @{ appid = 'sam'; name = 'CIPP Service'; amr = @('mfa'); scp = 'Directory.AccessAsUser.All User.Read' } }
            }
        }

        $Result = Test-CIPPAccessPermissions -TenantFilter 'partner'

        $Result.WarningMessages.Count | Should -Be 0
        $Result.UngrantedPermissions.Count | Should -Be 0
        $Result.Messages | Should -Contain 'All Microsoft Graph application permissions are granted to CIPP-SAM in your tenant.'
        $Result.Messages | Should -Contain 'All Microsoft Graph delegated permissions are granted to CIPP-SAM in your tenant.'
    }
}

# Pester tests for the request validation and protected-app check on Invoke-ExecManageAppCredentials.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [object]$ContentType
    }

    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$($Exception.Exception.Message)" } }
    function Get-CippProtectedAppId { }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $type, $body) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-IsGuid.ps1')
    $Endpoint = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Administration/Application Approval/Invoke-ExecManageAppCredentials.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $Endpoint -Raw)))

    $script:AppObj = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    $script:Protected = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'

    function New-Request {
        param([hashtable]$Body, [string[]]$Without = @())
        $Merged = @{ tenantFilter = 'contoso.onmicrosoft.com'; Id = $script:AppObj; AppType = 'applications'; CredentialType = 'password'; Action = 'Add'; DisplayName = 'test' }
        foreach ($Key in $Body.Keys) { $Merged[$Key] = $Body[$Key] }
        foreach ($Key in $Without) { $Merged.Remove($Key) }
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecManageAppCredentials' }; Headers = @{}; Query = [pscustomobject]@{}; Body = [pscustomobject]$Merged }
    }
}

Describe 'ExecManageAppCredentials request validation' {
    BeforeEach {
        Mock Get-CippProtectedAppId { $script:Protected }
        Mock New-GraphGetRequest { }
        Mock New-GraphPOSTRequest { [pscustomobject]@{ secretText = 's'; keyId = 'k' } }
        Mock Write-LogMessage { }
    }

    It 'refuses <Name>' -ForEach @(
        @{ Name = 'an AppType that is not an app collection'; Body = @{ AppType = 'users' } }
        @{ Name = 'a missing AppType'; Body = @{ AppType = $null } }
        @{ Name = 'an Id that walks the path'; Body = @{ Id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/owners' } }
        @{ Name = 'an AppId that closes the quote'; Body = @{ Id = $null; AppId = "x')/addPassword?x=('" } }
        @{ Name = 'a missing tenant'; Body = @{ tenantFilter = $null } }
    ) {
        $Response = Invoke-ExecManageAppCredentials -Request (New-Request -Body $Body)
        $Response.StatusCode | Should -Be 400
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'refuses <Action> on a protected app named by appId written as <AppId>' -ForEach @(
        @{ Action = 'Add'; AppId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' }
        @{ Action = 'Rotate'; AppId = '{bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb}' }
        @{ Action = 'Remove'; AppId = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB' }
    ) {
        $Response = Invoke-ExecManageAppCredentials -Request (New-Request -Body @{ Id = $null; AppId = $AppId; Action = $Action; KeyId = 'k' })
        $Response.StatusCode | Should -Be 403
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'refuses a protected app named by object id' {
        Mock New-GraphGetRequest { [pscustomobject]@{ appId = $script:Protected } } -ParameterFilter { $uri -like "*applications/$($script:AppObj)*select=appId*" }
        $Response = Invoke-ExecManageAppCredentials -Request (New-Request -Body @{})
        $Response.StatusCode | Should -Be 403
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'still adds a secret to an ordinary app' {
        Mock New-GraphGetRequest { [pscustomobject]@{ appId = 'cccccccc-cccc-cccc-cccc-cccccccccccc' } } -ParameterFilter { $uri -like '*select=appId*' }
        $Response = Invoke-ExecManageAppCredentials -Request (New-Request -Body @{})
        $Response.StatusCode | Should -Be 200
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $uri -eq "https://graph.microsoft.com/beta/applications/$($script:AppObj)/addPassword" }
    }
}

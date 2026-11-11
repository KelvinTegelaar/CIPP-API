# Pester tests for the request validation on Invoke-ExecApplication.

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
    function New-GraphGetRequest { param($Uri, $tenantid, $AsApp) }
    function New-GraphPOSTRequest { param($Uri, $Type, $Body, $tenantid, $AsApp, $AddedHeaders) }

    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Administration/Application Approval/Invoke-ExecApplication.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw)))

    $script:AppObjectId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    $script:ProtectedAppId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'

    function New-Request {
        param([hashtable]$Body, [string[]]$Without = @())
        $Merged = @{ Id = $script:AppObjectId; Type = 'applications'; tenantFilter = 'contoso.onmicrosoft.com'; Action = 'Update'; Payload = [pscustomobject]@{ displayName = 'Renamed' } }
        foreach ($Key in $Body.Keys) { $Merged[$Key] = $Body[$Key] }
        foreach ($Key in $Without) { $Merged.Remove($Key) }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecApplication' }
            Headers = @{}
            Query   = [pscustomobject]@{}
            Body    = [pscustomobject]$Merged
        }
    }
}

Describe 'ExecApplication request validation' {
    BeforeEach {
        Mock Get-CippProtectedAppId { $script:ProtectedAppId }
        Mock New-GraphGetRequest { [pscustomobject]@{ appId = 'cccccccc-cccc-cccc-cccc-cccccccccccc' } }
        Mock New-GraphPOSTRequest { }
    }

    It 'updates an application' {
        $Response = Invoke-ExecApplication -Request (New-Request)

        $Response.StatusCode | Should -Be 200
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq "https://graph.microsoft.com/beta/applications/$($script:AppObjectId)" -and $Type -eq 'PATCH' -and $Body -eq '{"displayName":"Renamed"}' -and $tenantid -eq 'contoso.onmicrosoft.com'
        }
    }

    It 'updates by appId' {
        $Response = Invoke-ExecApplication -Request (New-Request -Body @{ AppId = 'cccccccc-cccc-cccc-cccc-cccccccccccc' } -Without 'Id')

        $Response.StatusCode | Should -Be 200
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq "https://graph.microsoft.com/beta/applications(appId='cccccccc-cccc-cccc-cccc-cccccccccccc')" }
    }

    It 'rejects a request without <Name>' -ForEach @(
        @{ Name = 'a Type'; Without = @('Type') }
        @{ Name = 'a tenantFilter'; Without = @('tenantFilter') }
        @{ Name = 'an Id or AppId'; Without = @('Id') }
    ) {
        (Invoke-ExecApplication -Request (New-Request -Without $Without)).StatusCode | Should -Be 400
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'rejects <Name>' -ForEach @(
        @{ Name = 'an unknown Type'; Body = @{ Type = 'users' } }
        @{ Name = 'an Id that is not a GUID'; Body = @{ Id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa#/customers/x' } }
        @{ Name = 'an Id with a trailing newline'; Body = @{ Id = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa`n" } }
        @{ Name = 'an Id with a path';Body = @{ Id = '../users/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' } }
        @{ Name = 'an AppId that is not a GUID'; Body = @{ Id = $null; AppId = "x')/../../organization?a=('" } }
    ) {
        (Invoke-ExecApplication -Request (New-Request -Body $Body)).StatusCode | Should -Be 400
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'refuses <Name>' -ForEach @(
        @{ Name = 'a payload adding keyCredentials'; Body = @{ Payload = [pscustomobject]@{ keyCredentials = @() } } }
        @{ Name = 'an upsert adding passwordCredentials in any case'; Body = @{ Action = 'Upsert'; Payload = [pscustomobject]@{ PasswordCredentials = @() } } }
        @{ Name = 'a hashtable payload adding keyCredentials'; Body = @{ Payload = @{ KEYCREDENTIALS = @() } } }
    ) {
        (Invoke-ExecApplication -Request (New-Request -Body $Body)).StatusCode | Should -Be 400
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'refuses a protected app by appId' {
        $Response = Invoke-ExecApplication -Request (New-Request -Body @{ Action = 'Delete'; AppId = $script:ProtectedAppId } -Without 'Id')

        $Response.StatusCode | Should -Be 403
        Should -Invoke New-GraphPOSTRequest -Times 0
    }

    It 'refuses a protected app by object id' {
        Mock New-GraphGetRequest { [pscustomobject]@{ appId = $script:ProtectedAppId } } -ParameterFilter { $Uri -eq "https://graph.microsoft.com/beta/servicePrincipals/$($script:AppObjectId)?`$select=appId" }

        $Response = Invoke-ExecApplication -Request (New-Request -Body @{ Type = 'servicePrincipals'; Action = 'Delete' })

        $Response.StatusCode | Should -Be 403
        Should -Invoke New-GraphPOSTRequest -Times 0
    }
}

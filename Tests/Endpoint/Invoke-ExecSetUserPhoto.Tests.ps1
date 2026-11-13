# Pester tests for the request validation on Invoke-ExecSetUserPhoto.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [object]$ContentType
    }

    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$($Exception.Exception.Message)" } }
    function New-GraphPostRequest { param($uri, $tenantid, $type, $body, $ContentType, $NoAuthCheck) }

    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Identity/Administration/Users/Invoke-ExecSetUserPhoto.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw)))

    $script:UserId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    $script:Photo = 'data:image/jpeg;base64,' + [Convert]::ToBase64String([byte[]](1..16))
    function New-Request {
        param([hashtable]$Body)
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecSetUserPhoto' }; Headers = @{}; Query = [pscustomobject]@{}; Body = [pscustomobject]$Body }
    }
}

Describe 'ExecSetUserPhoto request validation' {
    BeforeEach {
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        Mock New-GraphPostRequest { $script:Calls.Add([pscustomobject]@{ Uri = $uri; Tenant = $tenantid; Type = $type; NoAuthCheck = $NoAuthCheck }) }
        Mock Write-LogMessage { }
    }

    It 'refuses <_> without a tenant' -ForEach @('remove', 'set') {
        $Response = Invoke-ExecSetUserPhoto -Request (New-Request -Body @{ userId = $script:UserId; action = $_; photoData = $script:Photo })
        $Response.StatusCode | Should -Be 400
        $script:Calls.Count | Should -Be 0
    }

    It 'refuses a user id of <_>' -ForEach @('..', '.') {
        $Response = Invoke-ExecSetUserPhoto -Request (New-Request -Body @{ userId = $_; action = 'remove'; tenantFilter = 'contoso.onmicrosoft.com' })
        $Response.StatusCode | Should -Be 400
        $script:Calls.Count | Should -Be 0
    }

    It 'keeps <Name> inside the user segment on <Action>' -ForEach @(
        @{ Name = 'a fragment'; Action = 'remove'; UserId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa#'; Expected = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa%23' }
        @{ Name = 'a path'; Action = 'remove'; UserId = '../groups/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb?x='; Expected = '..%2Fgroups%2Fbbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb%3Fx%3D' }
        @{ Name = 'a path'; Action = 'set'; UserId = '../groups/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb?x='; Expected = '..%2Fgroups%2Fbbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb%3Fx%3D' }
        @{ Name = 'a guest UPN'; Action = 'remove'; UserId = 'a_b.com#EXT#@contoso.onmicrosoft.com'; Expected = 'a_b.com%23EXT%23%40contoso.onmicrosoft.com' }
    ) {
        Invoke-ExecSetUserPhoto -Request (New-Request -Body @{ userId = $UserId; action = $Action; tenantFilter = 'contoso.onmicrosoft.com'; photoData = $script:Photo }) | Out-Null
        $script:Calls.Count | Should -Be 1
        $script:Calls[0].Uri | Should -BeExactly "https://graph.microsoft.com/v1.0/users/$Expected/photo/`$value"
    }

    It 'removes a photo for a named tenant with the tenant check on' {
        $Response = Invoke-ExecSetUserPhoto -Request (New-Request -Body @{ userId = $script:UserId; action = 'remove'; tenantFilter = 'contoso.onmicrosoft.com' })
        $Response.StatusCode | Should -Be 200
        $script:Calls[0].Type | Should -Be 'DELETE'
        $script:Calls[0].Tenant | Should -Be 'contoso.onmicrosoft.com'
        $script:Calls[0].NoAuthCheck | Should -BeNullOrEmpty
    }

    It 'sets a photo for a named tenant' {
        $Response = Invoke-ExecSetUserPhoto -Request (New-Request -Body @{ userId = $script:UserId; action = 'set'; tenantFilter = 'contoso.onmicrosoft.com'; photoData = $script:Photo })
        $Response.StatusCode | Should -Be 200
        $script:Calls[0].Type | Should -Be 'PUT'
    }
}

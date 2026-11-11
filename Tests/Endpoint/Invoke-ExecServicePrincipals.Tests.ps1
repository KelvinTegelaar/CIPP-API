# Pester tests for the request validation on Invoke-ExecServicePrincipals.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [object]$ContentType
    }

    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$($Exception.Exception.Message)" } }
    function New-GraphGetRequest { param($Uri, $tenantid, $NoAuthCheck, [switch]$ComplexFilter) }
    function New-GraphPostRequest { param($Uri, $tenantid, $type, $body, $NoAuthCheck) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-IsGuid.ps1')
    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Core/Invoke-ExecServicePrincipals.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw)))

    $script:Guid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    function New-Request {
        param([hashtable]$Query)
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecServicePrincipals' }; Headers = @{}; Query = [pscustomobject]$Query; Body = $null }
    }
}

Describe 'ExecServicePrincipals request validation' {
    BeforeEach {
        $env:TenantID = 'partner-tenant-id'
        Mock New-GraphGetRequest { [pscustomobject]@{ id = 'x' } }
        Mock New-GraphPostRequest { }
        Mock Write-LogMessage { }
    }

    It 'refuses <Name> without calling Graph' -ForEach @(
        @{ Name = 'an Id that walks up the path'; Query = @{ Id = '../organization' } }
        @{ Name = 'an Id with a query string'; Query = @{ Id = '../users?$top=1' } }
        @{ Name = 'an AppId that closes the quote'; Query = @{ AppId = "x')/../../users?x=('" } }
        @{ Name = 'a Select that adds a filter'; Query = @{ Select = 'id&$filter=accountEnabled eq true' } }
        @{ Name = 'a Select with a space'; Query = @{ Select = 'id, displayName' } }
    ) {
        $Response = Invoke-ExecServicePrincipals -Request (New-Request -Query $Query)
        $Response.StatusCode | Should -Be 400
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly
    }

    It 'gets a service principal by object id' {
        $Response = Invoke-ExecServicePrincipals -Request (New-Request -Query @{ Id = $script:Guid })
        $Response.StatusCode | Should -Be 200
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq "https://graph.microsoft.com/beta/servicePrincipals/$($script:Guid)" }
    }

    It 'gets a service principal by app id' {
        $Response = Invoke-ExecServicePrincipals -Request (New-Request -Query @{ AppId = $script:Guid })
        $Response.StatusCode | Should -Be 200
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq "https://graph.microsoft.com/beta/servicePrincipals(appId='$($script:Guid)')" }
    }

    It 'lists with the field selection the frontend sends' {
        $Response = Invoke-ExecServicePrincipals -Request (New-Request -Query @{ Select = 'appId,displayName,id' })
        $Response.StatusCode | Should -Be 200
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $Uri -like '*&$select=appId,displayName,id' }
    }

    It 'lists with no parameters' {
        (Invoke-ExecServicePrincipals -Request (New-Request -Query @{})).StatusCode | Should -Be 200
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly
    }

    It 'still refuses a malformed AppId on create' {
        $Response = Invoke-ExecServicePrincipals -Request (New-Request -Query @{ Action = 'Create'; AppId = 'not-a-guid' })
        $Response.StatusCode | Should -Be 400
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly
    }
}

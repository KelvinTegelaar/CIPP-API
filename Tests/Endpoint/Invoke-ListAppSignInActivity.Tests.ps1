# Pester tests for Invoke-ListAppSignInActivity and Set-CIPPDBCacheAppCredentialSignInActivities.
# The endpoint reads two caches; a cache never collected must read as unknown, not as "no sign-in".

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [object]$ContentType
    }

    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$($Exception.Exception.Message)" } }
    function Get-CIPPDbItem { param($TenantFilter, $Type) }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields, $Rows) }
    function New-GraphGetRequest { param($uri, $tenantid, [switch]$Stream) }
    function Add-CIPPDbItem {
        [CmdletBinding()]
        param($TenantFilter, $Type, [Parameter(ValueFromPipeline = $true)]$InputObject, $Data, [switch]$AddCount, [switch]$ClearOnEmpty)
        process { if ($InputObject) { $script:Written.Add($InputObject) } }
        end { if ($PSBoundParameters.ContainsKey('Data')) { $script:EmptyWrites++ } }
    }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheAppCredentialSignInActivities.ps1')
    $Endpoint = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Administration/Application Approval/Invoke-ListAppSignInActivity.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $Endpoint -Raw)))

    function Get-Activity {
        param($Tenant = 'contoso.onmicrosoft.com')
        Invoke-ListAppSignInActivity -Request ([pscustomobject]@{ Params = @{}; Headers = @{}; Query = [pscustomobject]@{ tenantFilter = $Tenant }; Body = $null })
    }
}

Describe 'Invoke-ListAppSignInActivity' {
    BeforeEach {
        $script:Caches = @{}
        Mock Get-CIPPDbItem {
            if (-not $script:Caches.ContainsKey($Type)) { return }
            [pscustomobject]@{ RowKey = "$Type-Count"; Timestamp = [datetime]'2026-11-03T02:00:00Z' }
            foreach ($Item in $script:Caches[$Type]) { [pscustomobject]@{ RowKey = "$Type-x"; Parsed = $Item } }
        }
        Mock New-CIPPDbRequest { foreach ($Row in $Rows) { $Row.Parsed } }
    }

    It 'returns the last sign-in of each app and credential with when each report was collected' {
        $script:Caches.ServicePrincipalSignInActivities = @([pscustomobject]@{
                appId                                         = 'app-1'
                lastSignInActivity                            = [pscustomobject]@{ lastSignInDateTime = '2026-11-01T10:00:00Z' }
                delegatedClientSignInActivity                 = [pscustomobject]@{ lastSignInDateTime = '2026-10-01T10:00:00Z' }
                applicationAuthenticationClientSignInActivity = [pscustomobject]@{ lastSignInDateTime = '2026-11-01T10:00:00Z' }
            })
        $script:Caches.AppCredentialSignInActivities = @([pscustomobject]@{ keyId = 'key-1'; appId = 'app-1'; credentialOrigin = 'application'; signInActivity = [pscustomobject]@{ lastSignInDateTime = '2026-11-01T10:00:00Z' } })

        $Response = Get-Activity
        $Result = $Response.Body.Results

        $Response.StatusCode | Should -Be 200
        $Result.appsCollected | Should -BeTrue
        $Result.appsCollectedAt | Should -Be ([datetime]'2026-11-03T02:00:00Z')
        $Result.apps[0].appId | Should -Be 'app-1'
        $Result.apps[0].lastSignInDateTime | Should -Be '2026-11-01T10:00:00Z'
        $Result.apps[0].lastDelegated | Should -Be '2026-10-01T10:00:00Z'
        $Result.credentials[0].keyId | Should -Be 'key-1'
        $Result.credentials[0].credentialOrigin | Should -Be 'application'
    }

    It 'says a report was never collected rather than returning an empty list as no sign-ins' {
        $script:Caches.ServicePrincipalSignInActivities = @()

        $Result = (Get-Activity).Body.Results

        $Result.appsCollected | Should -BeTrue
        @($Result.apps).Count | Should -Be 0
        $Result.credentialsCollected | Should -BeFalse
    }

    It 'refuses all tenants' {
        (Get-Activity -Tenant 'AllTenants').StatusCode | Should -Be 400
    }
}

Describe 'Set-CIPPDBCacheAppCredentialSignInActivities' {
    BeforeEach {
        $script:Written = [System.Collections.Generic.List[object]]::new()
        $script:EmptyWrites = 0
        Mock Write-LogMessage { }
    }

    It 'streams every row from the credential sign-in activity report into the cache' {
        Mock New-GraphGetRequest { [pscustomobject]@{ id = '1'; keyId = 'a' }; [pscustomobject]@{ id = '2'; keyId = 'b' } }

        Set-CIPPDBCacheAppCredentialSignInActivities -TenantFilter 'contoso.onmicrosoft.com'

        $script:Written.keyId | Should -Be @('a', 'b')
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -eq 'https://graph.microsoft.com/beta/reports/appCredentialSignInActivities' }
    }

    It 'records an empty report as an empty set' {
        Mock New-GraphGetRequest { }

        Set-CIPPDBCacheAppCredentialSignInActivities -TenantFilter 'contoso.onmicrosoft.com'

        $script:EmptyWrites | Should -Be 1
    }

    It 'writes nothing and rethrows when the report cannot be read' {
        Mock New-GraphGetRequest { throw 'Tenant does not have a SKU required for this feature' }

        { Set-CIPPDBCacheAppCredentialSignInActivities -TenantFilter 'contoso.onmicrosoft.com' } | Should -Throw '*SKU*'
        $script:Written.Count | Should -Be 0
        $script:EmptyWrites | Should -Be 0
    }
}

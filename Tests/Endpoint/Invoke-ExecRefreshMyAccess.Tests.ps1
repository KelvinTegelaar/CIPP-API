# Pester tests for Invoke-ExecRefreshMyAccess
#
# The endpoint is Public (a caller whose PIM elevation has not landed yet holds no CIPP
# role at all), so it must gate itself: identity comes only from the platform-injected
# principal header, API clients are refused, and a per-user cooldown caps how often the
# Graph-backed re-check can run.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecRefreshMyAccess.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecRefreshMyAccess.ps1 under Modules/' }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }

    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CippTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Test-CIPPAccessUserRole { param($User) }
    function Start-UserSyncTimer { }
    function Write-LogMessage { param($headers, $API, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) }

    . $FunctionPath

    function New-RefreshRequest {
        param(
            $Principal = @{ userDetails = 'user@contoso.com'; userRoles = @('authenticated', 'anonymous') },
            $Idp = 'azureStaticWebApps',
            $PrincipalName = 'user@contoso.com'
        )
        $Headers = @{
            'x-ms-client-principal-idp'  = $Idp
            'x-ms-client-principal-name' = $PrincipalName
        }
        if ($null -ne $Principal) {
            $Json = ConvertTo-Json -InputObject $Principal -Depth 5 -Compress
            $Headers['x-ms-client-principal'] = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Json))
        }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecRefreshMyAccess' }
            Headers = $Headers
            Body    = [pscustomobject]@{ }
        }
    }
}

Describe 'Invoke-ExecRefreshMyAccess' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippTable -MockWith { @{ TableName = 'cacheAccessUserRoles' } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $null }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Test-CIPPAccessUserRole -MockWith {
            [pscustomobject]@{
                userDetails = 'user@contoso.com'
                userRoles   = @('admin', 'authenticated', 'anonymous')
            }
        }
        Mock -CommandName Start-UserSyncTimer -MockWith { }
        Mock -CommandName Get-CippException -MockWith { @{ NormalizedError = 'boom' } }
    }

    It 'refreshes and returns the group-mapped roles for a signed-in user' {
        $Response = Invoke-ExecRefreshMyAccess -Request (New-RefreshRequest) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Roles | Should -Be @('admin')
        $Response.Body.Results | Should -Match 'admin'
        Should -Invoke Test-CIPPAccessUserRole -Times 1 -Exactly
        Should -Invoke Start-UserSyncTimer -Times 1 -Exactly
    }

    It 'seeds the re-check with placeholder roles only, never the principal roles' {
        # A stale principal can still carry old roles; baking them into the re-check would
        # write them straight back into the cache row this endpoint just cleared.
        $Request = New-RefreshRequest -Principal @{ userDetails = 'user@contoso.com'; userRoles = @('readonly', 'authenticated', 'anonymous') }
        $null = Invoke-ExecRefreshMyAccess -Request $Request -TriggerMetadata $null

        Should -Invoke Test-CIPPAccessUserRole -Times 1 -Exactly -ParameterFilter {
            ($User.userRoles -join ',') -eq 'authenticated,anonymous'
        }
    }

    It 'removes the cached role row before re-resolving' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{ PartitionKey = 'AccessUser'; RowKey = 'user@contoso.com'; Role = '["admin"]' }
        } -ParameterFilter { $Filter -like "*AccessUser*" }

        $Response = Invoke-ExecRefreshMyAccess -Request (New-RefreshRequest) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly
    }

    It 'reports when no group maps to a role' {
        Mock -CommandName Test-CIPPAccessUserRole -MockWith {
            [pscustomobject]@{
                userDetails = 'user@contoso.com'
                userRoles   = @('authenticated', 'anonymous')
            }
        }

        $Response = Invoke-ExecRefreshMyAccess -Request (New-RefreshRequest) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        @($Response.Body.Roles).Count | Should -Be 0
        $Response.Body.Results | Should -Match 'none of your Entra group memberships'
    }

    It 'enforces the cooldown between refreshes' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{ Timestamp = [System.DateTimeOffset]::UtcNow.AddSeconds(-5) }
        } -ParameterFilter { $Filter -like "*AccessRefresh*" }

        $Response = Invoke-ExecRefreshMyAccess -Request (New-RefreshRequest) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::TooManyRequests)
        Should -Invoke Test-CIPPAccessUserRole -Times 0 -Exactly
        Should -Invoke Start-UserSyncTimer -Times 0 -Exactly
        # A throttle the operator can't see is a throttle nobody can diagnose — the 429 must be logged.
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
            $API -eq 'RefreshMyAccess' -and $sev -eq 'Info' -and $message -match 'cooldown'
        }
    }

    It 'allows a refresh once the cooldown has elapsed' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            [pscustomobject]@{ Timestamp = [System.DateTimeOffset]::UtcNow.AddSeconds(-45) }
        } -ParameterFilter { $Filter -like "*AccessRefresh*" }

        $Response = Invoke-ExecRefreshMyAccess -Request (New-RefreshRequest) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Test-CIPPAccessUserRole -Times 1 -Exactly
    }

    It 'extracts the UPN from a claims-shaped principal' {
        $Claims = @{
            claims = @(
                @{ typ = 'preferred_username'; val = 'claims@contoso.com' }
            )
        }
        $null = Invoke-ExecRefreshMyAccess -Request (New-RefreshRequest -Principal $Claims -PrincipalName 'claims@contoso.com') -TriggerMetadata $null

        Should -Invoke Test-CIPPAccessUserRole -Times 1 -Exactly -ParameterFilter {
            $User.userDetails -eq 'claims@contoso.com'
        }
    }

    It 'refuses a request without a principal header' {
        $Response = Invoke-ExecRefreshMyAccess -Request (New-RefreshRequest -Principal $null) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::Unauthorized)
        Should -Invoke Test-CIPPAccessUserRole -Times 0 -Exactly
    }

    It 'refuses an app-only API client' {
        $Request = New-RefreshRequest -Principal @{
            userDetails = '11111111-2222-3333-4444-555555555555'
            userRoles   = @()
        } -Idp 'aad' -PrincipalName '11111111-2222-3333-4444-555555555555'

        $Response = Invoke-ExecRefreshMyAccess -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::Unauthorized)
        Should -Invoke Test-CIPPAccessUserRole -Times 0 -Exactly
    }

    It 'returns a server error when the refresh itself fails' {
        Mock -CommandName Test-CIPPAccessUserRole -MockWith { throw 'graph unavailable' }

        $Response = Invoke-ExecRefreshMyAccess -Request (New-RefreshRequest) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        $Response.Body.Results | Should -Match 'Failed to refresh access'
    }
}

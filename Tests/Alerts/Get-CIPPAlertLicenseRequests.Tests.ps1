# Pester tests for Get-CIPPAlertLicenseRequests

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AlertPath = Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertLicenseRequests.ps1'
    if (-not (Test-Path $AlertPath)) { throw "Could not locate Get-CIPPAlertLicenseRequests.ps1 at $AlertPath" }
    $TransientErrorPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CippTransientError.ps1'
    if (-not (Test-Path $TransientErrorPath)) { throw "Could not locate Test-CippTransientError.ps1 at $TransientErrorPath" }

    function Get-Tenants { [CmdletBinding()] param($TenantFilter, [switch]$SkipDomains) }
    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $scope, $noPagination) }
    function Get-CIPPLicenseSkuName { [CmdletBinding()] param($SkuIds, $TenantFilter) }
    function Get-CIPPTable { [CmdletBinding()] param($TableName) }
    function Get-CIPPAzDataTableEntity { [CmdletBinding()] param($Filter) }
    function New-CIPPDbRequest { [CmdletBinding()] param($TenantFilter, $Type, $Rows, $Fields) }
    function Write-AlertTrace { [CmdletBinding()] param($cmdletName, $tenantFilter, $data) }
    function Write-AlertMessage { [CmdletBinding()] param($message, $tenant, $tenantId, $LogData) }
    function Get-CippException { [CmdletBinding()] param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }

    . $TransientErrorPath
    . $AlertPath

    $script:Tenant = 'contoso.com'
    $script:TenantId = '11111111-2222-3333-4444-555555555555'
}

Describe 'Get-CIPPAlertLicenseRequests' {
    BeforeEach {
        $script:CapturedData = $null
        $script:TraceCalled = 0
        $script:CapturedUris = [System.Collections.Generic.List[string]]::new()
        $script:CapturedScope = $null
        $script:CapturedErrorMessage = $null
        $script:CapturedDbFilters = [System.Collections.Generic.List[string]]::new()

        Mock -CommandName Get-CIPPTable -MockWith { @{} }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($Filter)
            $script:CapturedDbFilters.Add($Filter)
            if ($Filter -like "*'Users-aaaaaaaa-0000-0000-0000-000000000001'*") { [pscustomobject]@{ id = 'aaaaaaaa-0000-0000-0000-000000000001'; userPrincipalName = 'adele@contoso.com'; displayName = 'Adele Vance' } }
        }
        Mock -CommandName New-CIPPDbRequest -MockWith { param($TenantFilter, $Type, $Rows, $Fields) $Rows }

        Mock -CommandName Get-Tenants -MockWith {
            [pscustomobject]@{ customerId = $script:TenantId; defaultDomainName = 'contoso.com'; initialDomainName = 'contoso.onmicrosoft.com' }
        }
        Mock -CommandName Get-CIPPLicenseSkuName -MockWith {
            [pscustomobject]@{ skuId = 'e0dfc8b9-9531-4ec8-94b4-9fec23b05fc8'; displayName = 'Microsoft Teams Exploratory Dept' }
        }
        Mock -CommandName Write-AlertTrace -MockWith {
            param($cmdletName, $tenantFilter, $data)
            $script:TraceCalled++
            $script:CapturedData = $data
        }
        Mock -CommandName Write-AlertMessage -MockWith {
            param($message, $tenant, $tenantId, $LogData)
            $script:CapturedErrorMessage = $message
        }
        Mock -CommandName New-GraphGetRequest -MockWith {
            param($uri, $tenantid, $scope, $noPagination)
            $script:CapturedUris.Add($uri)
            if ($uri -like '*self-service-requests*') {
                $script:CapturedScope = $scope
                return [pscustomobject]@{ items = @(
                        [pscustomobject]@{ requestId = 'req-1'; skuId = 'ab5128ae-2475-4d95-8c73-33f07d701bfc'; productId = 'CFQ7TTC0MM8R'; requestedBy = 'aaaaaaaa-0000-0000-0000-000000000001'; createdTime = '2026-05-28T18:36:35Z'; state = 'Pending' }
                        [pscustomobject]@{ requestId = 'req-2'; skuId = 'E0DFC8B9-9531-4EC8-94B4-9FEC23B05FC8'; productId = 'CFQ7TTC0JN4R'; requestedBy = 'aaaaaaaa-0000-0000-0000-000000000001'; requestReason = 'Need Teams'; createdTime = '2026-07-01T18:23:37Z'; state = 'Pending' }
                        [pscustomobject]@{ requestId = 'req-3'; skuId = '00000000-0000-0000-0000-000000000000'; productId = 'CFQ7TTCUNKNOWN'; requestedBy = 'aaaaaaaa-0000-0000-0000-000000000002'; createdTime = '2026-07-06T19:27:27Z'; state = 'Pending' }
                    ) }
            }
            if ($uri -like '*/users?*') {
                return @(
                    [pscustomobject]@{ id = 'aaaaaaaa-0000-0000-0000-000000000001'; userPrincipalName = 'adele@contoso.com'; displayName = 'Adele Vance' }
                    [pscustomobject]@{ id = 'aaaaaaaa-0000-0000-0000-000000000002'; userPrincipalName = 'megan@contoso.com'; displayName = 'Megan Bowen' }
                )
            }
            throw "Unexpected call: $uri"
        }
    }

    It 'reads the pending requests of the tenant from the licensing service with the admin portal scope' {
        Get-CIPPAlertLicenseRequests -TenantFilter $script:Tenant

        $script:CapturedUris[0] | Should -Be "https://admin.microsoft.com/fd/m365licensing/v1/tenants/$($script:TenantId)/self-service-requests?state=Pending"
        $script:CapturedScope | Should -Be 'https://admin.microsoft.com/.default'
    }

    It 'emits one item per request, keyed by the request ID, also when one user asks for several products' {
        Get-CIPPAlertLicenseRequests -TenantFilter $script:Tenant

        $script:TraceCalled | Should -Be 1
        @($script:CapturedData).Count | Should -Be 3
        @($script:CapturedData.Id) | Should -Be @('req-1', 'req-2', 'req-3')
        @($script:CapturedData | Where-Object { $_.UserId -eq 'aaaaaaaa-0000-0000-0000-000000000001' }).Count | Should -Be 2
        $script:CapturedData[0].PSObject.Properties.Name | Should -Not -Contain 'UserPrincipalName'
    }

    It 'names the product from the SKU name lookup and falls back to the product ID' {
        Get-CIPPAlertLicenseRequests -TenantFilter $script:Tenant

        $script:CapturedData[0].Product | Should -Be 'CFQ7TTC0MM8R'
        $script:CapturedData[1].Product | Should -Be 'Microsoft Teams Exploratory Dept'
        $script:CapturedData[2].Product | Should -Be 'CFQ7TTCUNKNOWN'
    }

    It 'resolves requesters from the users cache by row key and looks up only uncached users live' {
        Get-CIPPAlertLicenseRequests -TenantFilter $script:Tenant

        $script:CapturedData[0].UPN | Should -Be 'adele@contoso.com'
        $script:CapturedData[0].DisplayName | Should -Be 'Adele Vance'
        $script:CapturedData[2].UPN | Should -Be 'megan@contoso.com'
        $UserCalls = @($script:CapturedUris | Where-Object { $_ -like '*/users?*' })
        $UserCalls.Count | Should -Be 1
        $UserCalls[0] | Should -BeLike "*id in ('aaaaaaaa-0000-0000-0000-000000000002')*"
        $script:CapturedDbFilters | Should -HaveCount 2
        $script:CapturedDbFilters[0] | Should -Be "PartitionKey eq 'contoso.com' and RowKey ge 'Users-aaaaaaaa-0000-0000-0000-000000000001' and RowKey lt 'Users-aaaaaaaa-0000-0000-0000-000000000001.'"
        $script:CapturedData[0].Message | Should -Be 'adele@contoso.com requested a license for CFQ7TTC0MM8R'
    }

    It 'links to the License requests page of the tenant and keeps the reason' {
        Get-CIPPAlertLicenseRequests -TenantFilter $script:Tenant

        $script:CapturedData[0].LicenseRequestsUrl | Should -Be 'https://admin.cloud.microsoft/?delegatedOrg=contoso.onmicrosoft.com#/licenserequest'
        $script:CapturedData[1].Reason | Should -Be 'Need Teams'
    }

    It 'reports an empty run when there are no pending requests' {
        Mock -CommandName New-GraphGetRequest -MockWith { param($uri, $tenantid, $scope, $noPagination) [pscustomobject]@{ items = @() } }

        Get-CIPPAlertLicenseRequests -TenantFilter $script:Tenant

        $script:TraceCalled | Should -Be 1
        @($script:CapturedData | Where-Object { $_ }).Count | Should -Be 0
        Should -Invoke Get-CIPPLicenseSkuName -Times 0
    }

    It 'still emits requests when the user cache and the live lookup fail' {
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { throw 'table unavailable' }
        Mock -CommandName New-GraphGetRequest -MockWith {
            param($uri, $tenantid, $scope, $noPagination)
            if ($uri -like '*self-service-requests*') {
                return [pscustomobject]@{ items = @([pscustomobject]@{ requestId = 'req-9'; skuId = 'x'; productId = 'CFQ7TTC0MM8R'; requestedBy = 'aaaaaaaa-0000-0000-0000-000000000009'; createdTime = '2026-07-06T19:27:27Z'; state = 'Pending' }) }
            }
            throw 'Graph unavailable'
        }

        Get-CIPPAlertLicenseRequests -TenantFilter $script:Tenant

        $script:TraceCalled | Should -Be 1
        $script:CapturedData[0].Id | Should -Be 'req-9'
        $script:CapturedData[0].Message | Should -Be 'aaaaaaaa-0000-0000-0000-000000000009 requested a license for CFQ7TTC0MM8R'
    }

    It 'logs an error and does not emit when the licensing service fails' {
        Mock -CommandName New-GraphGetRequest -MockWith { throw 'Forbidden' }

        Get-CIPPAlertLicenseRequests -TenantFilter $script:Tenant

        $script:TraceCalled | Should -Be 0
        $script:CapturedErrorMessage | Should -Match 'LicenseRequests'
        $script:CapturedErrorMessage | Should -Match 'Forbidden'
    }
}

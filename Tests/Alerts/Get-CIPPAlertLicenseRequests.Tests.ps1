# Pester tests for Get-CIPPAlertLicenseRequests
#
# The alert reads the pending self-service license requests of a tenant from the admin center licensing
# service and emits one item per request through Write-AlertTrace. The item Id is the request ID, so each
# request alerts once, also when one user asks for several products.
#
# Write-AlertTrace is a lifecycle reconciler: a run that checked and found nothing must still call it once
# with empty data (that resolves handled requests), while a run that could not check must not call it.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AlertPath = Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertLicenseRequests.ps1'
    if (-not (Test-Path $AlertPath)) { throw "Could not locate Get-CIPPAlertLicenseRequests.ps1 at $AlertPath" }
    $TransientErrorPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CippTransientError.ps1'
    if (-not (Test-Path $TransientErrorPath)) { throw "Could not locate Test-CippTransientError.ps1 at $TransientErrorPath" }
    $env:CIPPRootPath = $RepoRoot

    function Get-Tenants { [CmdletBinding()] param($TenantFilter, [switch]$SkipDomains) }
    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $scope, $noPagination) }
    function New-CIPPDbRequest { [CmdletBinding()] param($TenantFilter, $Type, $Fields) }
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

        Mock -CommandName Get-Tenants -MockWith {
            [pscustomobject]@{ customerId = $script:TenantId; defaultDomainName = 'contoso.com'; initialDomainName = 'contoso.onmicrosoft.com' }
        }
        Mock -CommandName New-CIPPDbRequest -MockWith {
            @([pscustomobject]@{ id = 'user-1'; userPrincipalName = 'adele@contoso.com'; displayName = 'Adele Vance' })
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
                        [pscustomobject]@{ requestId = 'req-1'; skuId = 'ab5128ae-2475-4d95-8c73-33f07d701bfc'; productId = 'CFQ7TTC0MM8R'; requestedBy = 'user-1'; createdTime = '2026-05-28T18:36:35Z'; state = 'Pending' }
                        [pscustomobject]@{ requestId = 'req-2'; skuId = 'e0dfc8b9-9531-4ec8-94b4-9fec23b05fc8'; productId = 'CFQ7TTC0JN4R'; requestedBy = 'user-1'; requestReason = 'Need Teams'; createdTime = '2026-07-01T18:23:37Z'; state = 'Pending' }
                        [pscustomobject]@{ requestId = 'req-3'; skuId = '00000000-0000-0000-0000-000000000000'; productId = 'CFQ7TTCUNKNOWN'; requestedBy = 'user-2'; createdTime = '2026-07-06T19:27:27Z'; state = 'Pending' }
                    ) }
            }
            if ($uri -like '*/users/user-2*') {
                return [pscustomobject]@{ id = 'user-2'; userPrincipalName = 'megan@contoso.com'; displayName = 'Megan Bowen' }
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
        @($script:CapturedData | Where-Object { $_.UserId -eq 'user-1' }).Count | Should -Be 2
        $script:CapturedData[0].PSObject.Properties.Name | Should -Not -Contain 'UserPrincipalName'
    }

    It 'names the product from the conversion table, then from known product IDs, then falls back to the product ID' {
        Get-CIPPAlertLicenseRequests -TenantFilter $script:Tenant

        $script:CapturedData[0].Product | Should -Be 'Microsoft 365 Copilot'
        $script:CapturedData[1].Product | Should -Be 'Microsoft Teams Exploratory Dept'
        $script:CapturedData[2].Product | Should -Be 'CFQ7TTCUNKNOWN'
    }

    It 'resolves requesters from the user cache and looks up only users that are not cached' {
        Get-CIPPAlertLicenseRequests -TenantFilter $script:Tenant

        $script:CapturedData[0].UPN | Should -Be 'adele@contoso.com'
        $script:CapturedData[0].DisplayName | Should -Be 'Adele Vance'
        $script:CapturedData[2].UPN | Should -Be 'megan@contoso.com'
        @($script:CapturedUris | Where-Object { $_ -like '*/users/*' }).Count | Should -Be 1
        $script:CapturedData[0].Message | Should -Be 'adele@contoso.com requested a license for Microsoft 365 Copilot'
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
        Should -Invoke New-CIPPDbRequest -Times 0
    }

    It 'still emits requests when the user cache and the live lookup fail' {
        Mock -CommandName New-CIPPDbRequest -MockWith { throw 'cache unavailable' }
        Mock -CommandName New-GraphGetRequest -MockWith {
            param($uri, $tenantid, $scope, $noPagination)
            if ($uri -like '*self-service-requests*') {
                return [pscustomobject]@{ items = @([pscustomobject]@{ requestId = 'req-9'; skuId = 'x'; productId = 'CFQ7TTC0MM8R'; requestedBy = 'user-9'; createdTime = '2026-07-06T19:27:27Z'; state = 'Pending' }) }
            }
            throw 'Graph unavailable'
        }

        Get-CIPPAlertLicenseRequests -TenantFilter $script:Tenant

        $script:TraceCalled | Should -Be 1
        $script:CapturedData[0].Id | Should -Be 'req-9'
        $script:CapturedData[0].Message | Should -Be 'user-9 requested a license for Microsoft 365 Copilot'
    }

    It 'logs an error and does not emit when the licensing service fails' {
        Mock -CommandName New-GraphGetRequest -MockWith { throw 'Forbidden' }

        Get-CIPPAlertLicenseRequests -TenantFilter $script:Tenant

        $script:TraceCalled | Should -Be 0
        $script:CapturedErrorMessage | Should -Match 'LicenseRequests'
        $script:CapturedErrorMessage | Should -Match 'Forbidden'
    }
}

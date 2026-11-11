# Pester tests for Invoke-CIPPStandardOauthConsent and Invoke-CIPPStandardOauthConsentLowSec
#
# permissionGrantPolicyIdsAssignedToDefaultUserRole is a list. Next to the user consent entry
# (ManagePermissionGrantsForSelf.*) it carries ManagePermissionGrantsForOwnedResource.* entries for
# Teams/chat resource-specific consent. Comparing the list with -eq / -in graded a correct tenant
# wrong as soon as those entries were present, and the PATCH replaced the whole list.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    foreach ($Name in 'Invoke-CIPPStandardOauthConsent', 'Invoke-CIPPStandardOauthConsentLowSec') {
        $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter "$Name.ps1" -File -ErrorAction SilentlyContinue |
            Select-Object -First 1 -ExpandProperty FullName
        if (-not $StandardPath) { throw "Could not locate $Name.ps1 under Modules/" }
        . $StandardPath
    }

    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp) }
    function New-GraphPostRequest { [CmdletBinding()] param($tenantid, $uri, $type, $body, $AsApp, $ContentType) }
    function Get-CIPPStandards { [CmdletBinding()] param($Tenant) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $TenantFilter, $Tenant) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:Rsc = @(
        'ManagePermissionGrantsForOwnedResource.microsoft-dynamically-managed-permissions-for-team'
        'ManagePermissionGrantsForOwnedResource.microsoft-dynamically-managed-permissions-for-chat'
    )
    $script:Cipp = 'ManagePermissionGrantsForSelf.cipp-consent-policy'
    $script:Low = 'ManagePermissionGrantsForSelf.microsoft-user-default-low'
    $script:Legacy = 'ManagePermissionGrantsForSelf.microsoft-user-default-legacy'
    $script:DefaultInclude = [PSCustomObject]@{ permissionType = 'delegated'; permissionClassification = 'all'; clientApplicationIds = @('00b41c95-dab0-4487-9791-b9d2c32c80f2') }
}

Describe 'OAuth consent standards with resource-specific consent entries in the list' {
    BeforeEach {
        $script:Patches = [System.Collections.Generic.List[object]]::new()
        Mock New-GraphGetRequest {
            if ($uri -like '*authorizationPolicy*') { [PSCustomObject]@{ permissionGrantPolicyIdsAssignedToDefaultUserRole = $script:Assigned } }
            elseif ($uri -like '*cipp-consent-policy/includes*') { $script:DefaultInclude }
            elseif ($uri -like '*delegatedPermissionClassifications*') { 'offline_access', 'openid', 'User.Read', 'profile', 'email' | ForEach-Object { [PSCustomObject]@{ permissionName = $_ } } }
        }
        Mock New-GraphPostRequest { if ($type -eq 'PATCH') { $script:Patches.Add(($body | ConvertFrom-Json)) } }
        Mock Get-CIPPStandards { }
        Mock Write-LogMessage { }
        Mock Write-StandardsAlert { }
        Mock Set-CIPPStandardsCompareField { }
    }

    Context 'Invoke-CIPPStandardOauthConsent' {
        It 'grades a tenant with the CIPP policy plus RSC entries as correct and leaves it alone' {
            $script:Assigned = @($script:Cipp) + $script:Rsc

            Invoke-CIPPStandardOauthConsent -tenant $script:Tenant -settings @{ remediate = $true; alert = $true; report = $true }

            $script:Patches.Count | Should -Be 0
            Should -Invoke Write-StandardsAlert -Times 0 -Exactly
            Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
                (ConvertTo-Json @($CurrentValue.permissionGrantPolicyIdsAssignedToDefaultUserRole) -Compress) -eq (ConvertTo-Json @($ExpectedValue.permissionGrantPolicyIdsAssignedToDefaultUserRole) -Compress)
            }
        }

        It 'replaces the user consent entry and keeps the RSC entries when remediating' {
            $script:Assigned = @($script:Legacy) + $script:Rsc

            Invoke-CIPPStandardOauthConsent -tenant $script:Tenant -settings @{ remediate = $true }

            $script:Patches.Count | Should -Be 1
            $Sent = @($script:Patches[0].permissionGrantPolicyIdsAssignedToDefaultUserRole)
            $Sent | Should -Contain $script:Cipp
            $Sent | Should -Contain $script:Rsc[0]
            $Sent | Should -Contain $script:Rsc[1]
            $Sent | Should -Not -Contain $script:Legacy
        }

        It 'alerts when a second user consent policy is assigned next to the CIPP one' {
            $script:Assigned = @($script:Cipp, $script:Low)

            Invoke-CIPPStandardOauthConsent -tenant $script:Tenant -settings @{ alert = $true }

            Should -Invoke Write-StandardsAlert -Times 1 -Exactly
        }
    }

    Context 'Invoke-CIPPStandardOauthConsentLowSec' {
        It 'grades a tenant with the low policy plus RSC entries as correct and leaves it alone' {
            $script:Assigned = @($script:Low) + $script:Rsc

            Invoke-CIPPStandardOauthConsentLowSec -Tenant $script:Tenant -Settings @{ remediate = $true; alert = $true; report = $true }

            $script:Patches.Count | Should -Be 0
            Should -Invoke Write-StandardsAlert -Times 0 -Exactly
            Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
                (ConvertTo-Json @($CurrentValue.permissionGrantPolicyIdsAssignedToDefaultUserRole) -Compress) -eq (ConvertTo-Json @($ExpectedValue.permissionGrantPolicyIdsAssignedToDefaultUserRole) -Compress)
            }
        }

        It 'replaces the user consent entry and keeps the RSC entries when remediating' {
            $script:Assigned = @($script:Legacy) + $script:Rsc

            Invoke-CIPPStandardOauthConsentLowSec -Tenant $script:Tenant -Settings @{ remediate = $true; alert = $true }

            Should -Invoke Write-StandardsAlert -Times 1 -Exactly
            $script:Patches.Count | Should -Be 1
            $Sent = @($script:Patches[0].permissionGrantPolicyIdsAssignedToDefaultUserRole)
            $Sent | Should -Contain $script:Low
            $Sent | Should -Contain $script:Rsc[0]
            $Sent | Should -Contain $script:Rsc[1]
            $Sent | Should -Not -Contain $script:Legacy
        }
    }
}

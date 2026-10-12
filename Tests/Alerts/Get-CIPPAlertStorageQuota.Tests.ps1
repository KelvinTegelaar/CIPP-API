# Pester tests for the SharePoint and OneDrive storage quota alerts.
# Snoozes and alert lifecycle rows match items by Get-AlertContentHash, so an item that is still
# over its threshold must hash the same from run to run even as the usage figures move.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-GraphGetRequest { param($uri, $tenantid, $scope, $extraHeaders, $asapp, [switch]$UseCertificate) }
    function Get-SharePointAdminLink { param($Public, $tenantFilter) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($message, $API, $tenant, $sev, $LogData) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-AlertContentHash.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertSharepointQuota.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertOnedriveQuota.ps1')
}

Describe 'Storage quota alert content hash' {
    BeforeEach {
        $script:Captured = $null
        Mock Get-SharePointAdminLink { [pscustomobject]@{ AdminUrl = 'https://contoso-admin.sharepoint.com' } }
        Mock Write-AlertTrace {
            param($cmdletName, $tenantFilter, $data)
            $script:Captured = @($data | Where-Object { $null -ne $_ })
        }
    }

    It 'keeps the SharePoint quota item hash stable as usage changes' {
        Mock New-GraphGetRequest { [pscustomobject]@{ GeoUsedStorageMB = 950000; TenantStorageMB = 1000000 } }
        Get-CIPPAlertSharepointQuota -InputValue 90 -TenantFilter 'contoso.onmicrosoft.com'
        $First = $script:Captured

        Mock New-GraphGetRequest { [pscustomobject]@{ GeoUsedStorageMB = 960000; TenantStorageMB = 1000000 } }
        Get-CIPPAlertSharepointQuota -InputValue 90 -TenantFilter 'contoso.onmicrosoft.com'
        $Second = $script:Captured

        $First.Count | Should -Be 1
        $Second.Count | Should -Be 1
        $First[0].StorageUsed | Should -Not -Be $Second[0].StorageUsed
        (Get-AlertContentHash -AlertItem $Second[0]).ContentHash | Should -Be (Get-AlertContentHash -AlertItem $First[0]).ContentHash
    }

    It 'keeps each OneDrive quota item hash stable as usage changes, and distinct per owner' {
        $script:Used = 95GB
        Mock New-GraphGetRequest {
            @(
                [pscustomobject]@{ ownerPrincipalName = 'a@contoso.com'; storageUsedInBytes = $script:Used; storageAllocatedInBytes = 100GB }
                [pscustomobject]@{ ownerPrincipalName = 'b@contoso.com'; storageUsedInBytes = $script:Used; storageAllocatedInBytes = 100GB }
            )
        }
        Get-CIPPAlertOneDriveQuota -InputValue 90 -TenantFilter 'contoso.onmicrosoft.com'
        $First = $script:Captured

        $script:Used = 97GB
        Get-CIPPAlertOneDriveQuota -InputValue 90 -TenantFilter 'contoso.onmicrosoft.com'
        $Second = $script:Captured

        $First.Count | Should -Be 2
        $First[0].UsagePercent | Should -Not -Be $Second[0].UsagePercent
        (Get-AlertContentHash -AlertItem $Second[0]).ContentHash | Should -Be (Get-AlertContentHash -AlertItem $First[0]).ContentHash
        (Get-AlertContentHash -AlertItem $First[1]).ContentHash | Should -Not -Be (Get-AlertContentHash -AlertItem $First[0]).ContentHash
    }
}

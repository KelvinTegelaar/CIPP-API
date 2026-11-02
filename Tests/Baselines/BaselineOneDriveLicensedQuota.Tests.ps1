# OneDriveLicensedQuota: the OneDriveQuotas collector caches every licensed user's drive quota, the
# hook decides which entitled users' OneDrives sit below 5 TB from the Users and OneDriveQuotas
# caches, and the executor raises each personal site through one Set-CIPPSPOSiteBulk batch. These
# pin the collector's request and row shape, the entitlement rules, the five-user gate, the
# never-lower rule and the write shape.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Get-CIPPBaselineCacheRows { param($TenantFilter, $Type, $CollectorType, $CollectorArgs) }
    function Test-CIPPBaselineCacheCollected { param($TenantFilter, $Type) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }
    function New-GraphBulkRequest { param($tenantid, $Requests, $asapp, $Version, $scope) }
    function Set-CIPPSPOSiteBulk { param($TenantFilter, $Sites, $MaxConcurrency, $MaxRetries, [switch]$UseCertificate) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev) }
    . (Join-Path $script:RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheOneDriveQuotas.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/PrepareHooks/Get-CIPPBaselineOneDriveLicensedQuotaState.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Executors/Invoke-CIPPBaselineOneDriveLicensedQuota.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:SPPlan2 = '5dbe027f-2339-4123-9542-606e4d348a72'
    $script:ODPlan2 = 'afcafa6a-d966-4462-918c-ec0b4e0fe642'

    function script:New-TestUser {
        param([string]$Id, [bool]$Enabled = $true, [string]$PlanId = $script:SPPlan2, [string]$PlanStatus = 'Enabled')
        [PSCustomObject]@{
            id                = $Id
            userPrincipalName = "$Id@contoso.com"
            accountEnabled    = $Enabled
            assignedLicenses  = @([PSCustomObject]@{ skuId = 'sku' })
            assignedPlans     = @([PSCustomObject]@{ servicePlanId = $PlanId; capabilityStatus = $PlanStatus })
        }
    }
    function script:New-QuotaRow {
        param([string]$Id, [int64]$Total)
        [PSCustomObject]@{
            id                = $Id
            userPrincipalName = "$Id@contoso.com"
            quotaTotal        = $Total
            webUrl            = "https://contoso-my.sharepoint.com/personal/$($Id)_contoso_com/Documents"
        }
    }
    function script:New-Drive {
        param([string]$Id, [int64]$Total, [int]$Status = 200)
        [PSCustomObject]@{
            id     = $Id
            status = $Status
            body   = [PSCustomObject]@{
                webUrl = "https://contoso-my.sharepoint.com/personal/$($Id)_contoso_com/Documents"
                quota  = [PSCustomObject]@{ total = $Total }
            }
        }
    }
    $script:FiveEntitled = @(1..5 | ForEach-Object { New-TestUser "u$_" })
    $script:Definition = Get-Content (Join-Path $script:RepoRoot 'Config/BaselineStandards/SharePoint Standards/OneDriveLicensedQuota.json') -Raw | ConvertFrom-Json
}

Describe 'OneDriveLicensedQuota definition' {
    It 'keeps the classic name, grades an empty offender set and routes to its executor' {
        $script:Definition.name | Should -Be 'OneDriveLicensedQuota'
        @($script:Definition.expected.offenders).Count | Should -Be 0
        $script:Definition.prepare | Should -Be 'Get-CIPPBaselineOneDriveLicensedQuotaState'
        $script:Definition.remediate.executor | Should -Be 'OneDriveLicensedQuota'
    }

    It 'reads the OneDriveQuotas cache and keeps it fresh through requiredCaches' {
        $script:Definition.read.cacheType | Should -Be 'OneDriveQuotas'
        @($script:Definition.read.requiredCaches) | Should -Be @('OneDriveQuotas')
    }

    It 'registers the OneDriveQuotas cache type' {
        $Types = Get-Content (Join-Path $script:RepoRoot 'Config/CIPPDBCacheTypes.json') -Raw | ConvertFrom-Json
        @($Types.Where({ $_.type -eq 'OneDriveQuotas' })).Count | Should -Be 1
    }
}

Describe 'Set-CIPPDBCacheOneDriveQuotas' {
    BeforeEach {
        $script:Written = $null
        Mock Write-LogMessage {}
        Mock New-CIPPDbRequest { $script:FiveEntitled }
        Mock New-GraphBulkRequest { @($Requests | ForEach-Object { New-Drive $_.id 1TB }) }
        Mock Add-CIPPDbItem { $script:Written = @($Data) }
    }

    It 'reads every enabled licensed user''s drive app-only and writes one row per drive' {
        Set-CIPPDBCacheOneDriveQuotas -TenantFilter $script:Tenant
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { $asapp -eq $true -and @($Requests).Count -eq 5 -and $Requests[0].url -like 'users/*/drive?$select=quota,webUrl' }
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $Type -eq 'OneDriveQuotas' -and $AddCount -and $ClearOnEmpty }
        $script:Written.Count | Should -Be 5
        $Row = $script:Written.Where({ $_.id -eq 'u1' })[0]
        $Row.userPrincipalName | Should -Be 'u1@contoso.com'
        $Row.quotaTotal | Should -Be 1TB
        $Row.webUrl | Should -Be 'https://contoso-my.sharepoint.com/personal/u1_contoso_com/Documents'
    }

    It 'skips disabled and unlicensed users' {
        $Unlicensed = New-TestUser 'nolic'
        $Unlicensed.assignedLicenses = @()
        Mock New-CIPPDbRequest { @($script:FiveEntitled[0]) + @(New-TestUser 'off' -Enabled $false) + @($Unlicensed) }
        Set-CIPPDBCacheOneDriveQuotas -TenantFilter $script:Tenant
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter { @($Requests).Count -eq 1 -and $Requests[0].id -eq 'u1' }
    }

    It 'writes no row for an unprovisioned drive' {
        Mock New-GraphBulkRequest { @((New-Drive 'u1' 1TB), (New-Drive 'u2' 1TB -Status 404)) }
        Set-CIPPDBCacheOneDriveQuotas -TenantFilter $script:Tenant
        @($script:Written.id) | Should -Be @('u1')
        Should -Invoke Write-LogMessage -Times 0 -ParameterFilter { $Sev -eq 'Warning' }
    }

    It 'writes an empty set, without warning, when no OneDrive is provisioned yet' {
        Mock New-GraphBulkRequest { @((New-Drive 'u1' 1TB -Status 404), (New-Drive 'u2' 1TB -Status 404)) }
        Set-CIPPDBCacheOneDriveQuotas -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly
        @($script:Written).Count | Should -Be 0
        Should -Invoke Write-LogMessage -Times 0 -ParameterFilter { $Sev -eq 'Warning' }
    }

    It 'writes nothing while the Users cache is empty, so it never reads as collected' {
        Mock New-CIPPDbRequest { @() }
        Set-CIPPDBCacheOneDriveQuotas -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 0
        Should -Invoke New-GraphBulkRequest -Times 0
    }

    It 'writes an empty collection when no user is licensed' {
        Mock New-CIPPDbRequest { @(New-TestUser 'off' -Enabled $false) }
        Set-CIPPDBCacheOneDriveQuotas -TenantFilter $script:Tenant
        Should -Invoke New-GraphBulkRequest -Times 0
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly
        $script:Written.Count | Should -Be 0
    }

    It 'keeps the drives it could read and warns about the rest' {
        Mock New-GraphBulkRequest { @((New-Drive 'u1' 1TB), (New-Drive 'u2' 1TB -Status 403)) }
        Set-CIPPDBCacheOneDriveQuotas -TenantFilter $script:Tenant
        @($script:Written.id) | Should -Be @('u1')
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Warning' -and $message -like '*1 of 2*' }
    }

    It 'throws without writing when every drive read fails (<Case>)' -ForEach @(
        @{ Case = 'all forbidden'; Statuses = @(403, 403) }
        @{ Case = 'one unprovisioned, the rest forbidden'; Statuses = @(404, 403) }
    ) {
        $script:Statuses = $Statuses
        Mock New-GraphBulkRequest { @((New-Drive 'u1' 1TB -Status $script:Statuses[0]), (New-Drive 'u2' 1TB -Status $script:Statuses[1])) }
        { Set-CIPPDBCacheOneDriveQuotas -TenantFilter $script:Tenant } | Should -Throw '*every OneDrive quota read failed*'
        Should -Invoke Add-CIPPDbItem -Times 0
    }

    It 'throws without writing when the drive read fails' {
        Mock New-GraphBulkRequest { throw 'boom' }
        { Set-CIPPDBCacheOneDriveQuotas -TenantFilter $script:Tenant } | Should -Throw '*boom*'
        Should -Invoke Add-CIPPDbItem -Times 0
    }
}

Describe 'Get-CIPPBaselineOneDriveLicensedQuotaState' {
    BeforeEach {
        $script:Quotas = @(1..5 | ForEach-Object { New-QuotaRow "u$_" 1TB })
        Mock Get-CIPPBaselineCacheRows { $script:FiveEntitled }
        Mock Test-CIPPBaselineCacheCollected { $true }
        Mock New-CIPPDbRequest { $script:Quotas }
    }

    It 'reports No Data when the Users cache is empty' {
        Mock Get-CIPPBaselineCacheRows { @() }
        (Get-CIPPBaselineOneDriveLicensedQuotaState -Item $null -TenantFilter $script:Tenant).Current | Should -BeNullOrEmpty
    }

    It 'reports No Data when the OneDriveQuotas cache was never collected' {
        Mock Test-CIPPBaselineCacheCollected { $false }
        (Get-CIPPBaselineOneDriveLicensedQuotaState -Item $null -TenantFilter $script:Tenant).Current | Should -BeNullOrEmpty
    }

    It 'flags every entitled drive below 5 TB from the cache and targets the personal site' {
        $Prepared = Get-CIPPBaselineOneDriveLicensedQuotaState -Item $null -TenantFilter $script:Tenant
        @($Prepared.Current.offenders) | Should -Be @('u1@contoso.com', 'u2@contoso.com', 'u3@contoso.com', 'u4@contoso.com', 'u5@contoso.com')
        $Target = @($Prepared.Current.targets | Where-Object userPrincipalName -EQ 'u1@contoso.com')[0]
        $Target.siteUrl | Should -Be 'https://contoso-my.sharepoint.com/personal/u1_contoso_com'
        $Target.currentQuotaGB | Should -Be 1024
        $Target.targetQuotaGB | Should -Be 5120
        Should -Invoke Get-CIPPBaselineCacheRows -Times 1 -Exactly -ParameterFilter { $Type -eq 'Users' }
        Should -Invoke New-CIPPDbRequest -Times 1 -Exactly -ParameterFilter { $Type -eq 'OneDriveQuotas' }
    }

    It 'treats a collected but empty quota cache as compliant' {
        $script:Quotas = @()
        $Prepared = Get-CIPPBaselineOneDriveLicensedQuotaState -Item $null -TenantFilter $script:Tenant
        $Prepared.Current | Should -Not -BeNullOrEmpty
        @($Prepared.Current.offenders).Count | Should -Be 0
    }

    It 'is compliant without reading quotas when fewer than five users are entitled' {
        Mock Get-CIPPBaselineCacheRows { @($script:FiveEntitled[0..3]) + @(New-TestUser 'off' -Enabled $false) + @(New-TestUser 'dis' -PlanStatus 'Suspended') + @(New-TestUser 'oth' -PlanId 'other-plan') }
        $Prepared = Get-CIPPBaselineOneDriveLicensedQuotaState -Item $null -TenantFilter $script:Tenant
        @($Prepared.Current.offenders).Count | Should -Be 0
        $Prepared.Current | Should -Not -BeNullOrEmpty
        Should -Invoke New-CIPPDbRequest -Times 0
    }

    It 'counts the OneDrive Plan 2 service plan as entitling' {
        Mock Get-CIPPBaselineCacheRows { @($script:FiveEntitled[0..3]) + @(New-TestUser 'od' -PlanId $script:ODPlan2) }
        $script:Quotas = @(New-QuotaRow 'od' 1TB)
        $Prepared = Get-CIPPBaselineOneDriveLicensedQuotaState -Item $null -TenantFilter $script:Tenant
        @($Prepared.Current.offenders) | Should -Contain 'od@contoso.com'
    }

    It 'ignores cached drives of users who are not entitled' {
        $script:Quotas = @((New-QuotaRow 'u1' 1TB), (New-QuotaRow 'stranger' 1TB))
        @((Get-CIPPBaselineOneDriveLicensedQuotaState -Item $null -TenantFilter $script:Tenant).Current.offenders) | Should -Be @('u1@contoso.com')
    }

    It 'never lowers a drive at or above 5 TB and skips quota-less drives' {
        $script:Quotas = @((New-QuotaRow 'u1' 5TB), (New-QuotaRow 'u2' 25TB), (New-QuotaRow 'u4' 0), (New-QuotaRow 'u5' 1TB))
        @((Get-CIPPBaselineOneDriveLicensedQuotaState -Item $null -TenantFilter $script:Tenant).Current.offenders) | Should -Be @('u5@contoso.com')
    }

    It 'skips a drive whose site is not a personal site' {
        $Row = New-QuotaRow 'u1' 1TB
        $Row.webUrl = 'https://contoso.sharepoint.com/sites/team/Documents'
        $script:Quotas = @($Row)
        @((Get-CIPPBaselineOneDriveLicensedQuotaState -Item $null -TenantFilter $script:Tenant).Current.offenders).Count | Should -Be 0
    }
}

Describe 'Invoke-CIPPBaselineOneDriveLicensedQuota' {
    BeforeEach {
        $script:Sent = $null
        Mock Write-LogMessage {}
        Mock Set-CIPPSPOSiteBulk { $script:Sent = $Sites; @($Sites | ForEach-Object { [PSCustomObject]@{ SiteUrl = $_.SiteUrl; Success = $true } }) }
        $script:Current = [PSCustomObject]@{
            targets = @(
                [PSCustomObject]@{ userPrincipalName = 'a@contoso.com'; currentQuotaGB = 1024; targetQuotaGB = 5120; siteUrl = 'https://contoso-my.sharepoint.com/personal/a' }
                [PSCustomObject]@{ userPrincipalName = 'b@contoso.com'; currentQuotaGB = 1024; targetQuotaGB = 5120; siteUrl = 'https://contoso-my.sharepoint.com/personal/b' }
            )
        }
    }

    It 'writes 5 TB with a 90% warning level to each site in one certificate batch' {
        Invoke-CIPPBaselineOneDriveLicensedQuota -Remediate $null -TenantFilter $script:Tenant -Current $script:Current
        Should -Invoke Set-CIPPSPOSiteBulk -Times 1 -Exactly -ParameterFilter { $UseCertificate -eq $true }
        @($script:Sent).Count | Should -Be 2
        $script:Sent[0].SiteUrl | Should -Be 'https://contoso-my.sharepoint.com/personal/a'
        $script:Sent[0].Properties.StorageMaximumLevel | Should -Be 5242880
        $script:Sent[0].Properties.StorageWarningLevel | Should -Be 4718592
    }

    It 'does nothing without targets' {
        Invoke-CIPPBaselineOneDriveLicensedQuota -Remediate $null -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ targets = @() })
        Should -Invoke Set-CIPPSPOSiteBulk -Times 0
    }

    It 'continues past a partial failure' {
        Mock Set-CIPPSPOSiteBulk { @([PSCustomObject]@{ SiteUrl = 'https://contoso-my.sharepoint.com/personal/a'; Success = $true }, [PSCustomObject]@{ SiteUrl = 'https://contoso-my.sharepoint.com/personal/b'; Success = $false; Error = 'denied' }) }
        { Invoke-CIPPBaselineOneDriveLicensedQuota -Remediate $null -TenantFilter $script:Tenant -Current $script:Current } | Should -Not -Throw
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Error' }
    }

    It 'throws when every write failed' {
        Mock Set-CIPPSPOSiteBulk { @($Sites | ForEach-Object { [PSCustomObject]@{ SiteUrl = $_.SiteUrl; Success = $false; Error = 'denied' } }) }
        { Invoke-CIPPBaselineOneDriveLicensedQuota -Remediate $null -TenantFilter $script:Tenant -Current $script:Current } | Should -Throw '*all 2*'
    }
}

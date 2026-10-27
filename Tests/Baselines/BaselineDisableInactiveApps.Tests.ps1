# Get-CIPPBaselineDisableInactiveAppsState decides which enterprise apps the sweep disables. Each test
# pins one rule that keeps a used or protected app out of that set, or one that puts an idle app in it.
# Get-CIPPTextReplacement and Get-CIPPVendorTenantMap run for real so list-variable expansion and the
# Microsoft tenant list are exercised as shipped; only storage and Graph are stubbed.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function New-CIPPDbRequest { param($TenantFilter, $Type) }
    function Get-CIPPBaselineCacheRows { param($TenantFilter, $Type) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-Tenants { param($TenantFilter) }
    function Get-CIPPTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Filter) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPTextReplacement.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/AppPermissions/Get-CIPPVendorTenantMap.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/PrepareHooks/Get-CIPPBaselineDisableInactiveAppsState.ps1')

    $script:SavedRoot = $env:CIPPRootPath
    $script:SavedAppId = $env:ApplicationID
    $env:CIPPRootPath = $script:RepoRoot
    $env:ApplicationID = 'cipp-app'

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:Now = [datetime]::UtcNow

    function script:New-App {
        param(
            [string]$Name,
            [string]$Owner = '11111111-1111-1111-1111-111111111111',
            [int]$CreatedDaysAgo = 400,
            [bool]$Enabled = $true,
            [string]$Type = 'Application',
            [string]$AppId = "app-$Name"
        )
        [pscustomobject]@{
            id                     = "sp-$Name"
            appId                  = $AppId
            displayName            = $Name
            accountEnabled         = $Enabled
            servicePrincipalType   = $Type
            appOwnerOrganizationId = $Owner
            createdDateTime        = $script:Now.AddDays(-$CreatedDaysAgo).ToString('o')
        }
    }

    function script:New-Activity {
        param([string]$AppId, [int]$DaysAgo)
        [pscustomobject]@{ appId = $AppId; lastSignInActivity = [pscustomobject]@{ lastSignInDateTime = $script:Now.AddDays(-$DaysAgo).ToString('o') } }
    }

    function script:New-AppsItem {
        param($Days = 90, $Excluded)
        $Variables = [pscustomobject]@{ days = $Days }
        if ($Excluded) { $Variables | Add-Member -NotePropertyName excludedApps -NotePropertyValue @($Excluded | ForEach-Object { [pscustomobject]@{ label = $_; value = $_ } }) }
        [pscustomobject]@{ Variables = $Variables }
    }
}

AfterAll {
    $env:CIPPRootPath = $script:SavedRoot
    $env:ApplicationID = $script:SavedAppId
}

Describe 'Get-CIPPBaselineDisableInactiveAppsState' {
    BeforeEach {
        $script:Apps = @()
        $script:Activity = @()
        $script:CollectedDaysAgo = 0
        $script:Audits = @()
        $script:Variables = @()
        Mock New-CIPPDbRequest { $script:Apps }
        Mock Get-CIPPBaselineCacheRows { $script:Activity }
        Mock Get-CIPPDbItem { if ($null -ne $script:CollectedDaysAgo) { [pscustomobject]@{ Timestamp = [datetimeoffset]$script:Now.AddDays(-$script:CollectedDaysAgo) } } }
        Mock New-GraphGetRequest { $script:Audits }
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'cust-1'; defaultDomainName = $script:Tenant } }
        Mock Get-CIPPTable { @{} }
        Mock Get-CIPPAzDataTableEntity { param($Filter) if ($Filter -like "*'AllTenants'*") { $script:Variables } }
    }

    It 'flags an app idle past the window and leaves a recently used one' {
        $script:Apps = @((New-App 'Idle'), (New-App 'Busy'))
        $script:Activity = @((New-Activity 'app-Idle' 120), (New-Activity 'app-Busy' 5))

        $Prepared = Get-CIPPBaselineDisableInactiveAppsState -Item (New-AppsItem) -TenantFilter $script:Tenant

        @($Prepared.Current.offenders) | Should -Be @('Idle (app-Idle)')
        @($Prepared.Current.targets).id | Should -Be @('sp-Idle')
    }

    It 'flags a never-used app only once it is older than the window' {
        $script:Apps = @((New-App 'OldUnused' -CreatedDaysAgo 120), (New-App 'NewUnused' -CreatedDaysAgo 20))

        $Prepared = Get-CIPPBaselineDisableInactiveAppsState -Item (New-AppsItem) -TenantFilter $script:Tenant

        @($Prepared.Current.offenders) | Should -Be @('OldUnused (app-OldUnused)')
    }

    It 'gives an app recreated inside the window its grace even with an old sign-in on its appId' {
        $script:Apps = @(New-App 'Recreated' -CreatedDaysAgo 10)
        $script:Activity = @(New-Activity 'app-Recreated' 400)

        $Prepared = Get-CIPPBaselineDisableInactiveAppsState -Item (New-AppsItem) -TenantFilter $script:Tenant

        @($Prepared.Current.offenders) | Should -BeNullOrEmpty
    }

    It 'never flags Microsoft-owned apps, managed identities, disabled apps or CIPP itself' {
        $script:Apps = @(
            New-App 'MsServices' -Owner 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'
            New-App 'MsAme' -Owner '33e01921-4d64-4f8c-a055-5bdaffd5e33d'
            New-App 'Identity' -Type 'ManagedIdentity'
            New-App 'AlreadyOff' -Enabled $false
            New-App 'CIPP-SAM' -AppId 'cipp-app'
            New-App 'ThirdParty'
        )

        $Prepared = Get-CIPPBaselineDisableInactiveAppsState -Item (New-AppsItem) -TenantFilter $script:Tenant

        @($Prepared.Current.offenders) | Should -Be @('ThirdParty (app-ThirdParty)')
    }

    It 'measures the window from when the sign-in report was collected, not from now' {
        $script:CollectedDaysAgo = 100
        $script:Apps = @(New-App 'UsedBeforeStaleReport')
        $script:Activity = @(New-Activity 'app-UsedBeforeStaleReport' 110)

        $Prepared = Get-CIPPBaselineDisableInactiveAppsState -Item (New-AppsItem -Days 30) -TenantFilter $script:Tenant

        @($Prepared.Current.offenders) | Should -BeNullOrEmpty
    }

    It 'returns No Data when the sign-in report was never collected' {
        $script:CollectedDaysAgo = $null
        $script:Apps = @(New-App 'Idle')

        (Get-CIPPBaselineDisableInactiveAppsState -Item (New-AppsItem) -TenantFilter $script:Tenant).Current | Should -BeNullOrEmpty
    }

    It 'returns No Data when no service principals are cached' {
        (Get-CIPPBaselineDisableInactiveAppsState -Item (New-AppsItem) -TenantFilter $script:Tenant).Current | Should -BeNullOrEmpty
    }

    It 'leaves an app an admin re-enabled in the last 7 days alone' {
        $script:Apps = @((New-App 'Reenabled'), (New-App 'RequiresAssignment'))
        $script:Audits = @(
            [pscustomobject]@{ targetResources = @([pscustomobject]@{ id = 'sp-Reenabled'; modifiedProperties = @([pscustomobject]@{ displayName = 'AccountEnabled'; oldValue = '[false]'; newValue = '[true]' }) }) }
            [pscustomobject]@{ targetResources = @([pscustomobject]@{ id = 'sp-RequiresAssignment'; modifiedProperties = @([pscustomobject]@{ displayName = 'AppRoleAssignmentRequired'; oldValue = '[false]'; newValue = '[true]' }) }) }
        )

        $Prepared = Get-CIPPBaselineDisableInactiveAppsState -Item (New-AppsItem) -TenantFilter $script:Tenant

        @($Prepared.Current.offenders) | Should -Be @('RequiresAssignment (app-RequiresAssignment)')
    }

    It 'excludes by display name, app ID or object ID, ignoring case' {
        $script:Apps = @((New-App 'ByName'), (New-App 'ByAppId'), (New-App 'ByObjectId'), (New-App 'Kept'))

        $Prepared = Get-CIPPBaselineDisableInactiveAppsState -Item (New-AppsItem -Excluded 'byname', 'APP-BYAPPID', 'sp-ByObjectId') -TenantFilter $script:Tenant

        @($Prepared.Current.offenders) | Should -Be @('Kept (app-Kept)')
    }

    It 'expands a List variable into one exclusion per value and dedupes the result' {
        $script:Variables = @([pscustomobject]@{ RowKey = 'protectedapps'; Value = '["Vendor A","app-VendorB","Vendor A"]'; VariableType = 'list' })
        $script:Apps = @((New-App 'Vendor A'), (New-App 'VendorB'), (New-App 'Kept'))

        $Prepared = Get-CIPPBaselineDisableInactiveAppsState -Item (New-AppsItem -Excluded '%protectedapps%', 'vendor a') -TenantFilter $script:Tenant

        @($Prepared.Current.offenders) | Should -Be @('Kept (app-Kept)')
    }

    It 'drops an empty List variable instead of treating it as an app name' {
        $script:Variables = @([pscustomobject]@{ RowKey = 'protectedapps'; Value = '[]'; VariableType = 'list' })
        $script:Apps = @(New-App 'Kept')

        $Prepared = Get-CIPPBaselineDisableInactiveAppsState -Item (New-AppsItem -Excluded '%protectedapps%') -TenantFilter $script:Tenant

        @($Prepared.Current.offenders) | Should -Be @('Kept (app-Kept)')
    }

    It 'resolves a plain string variable as one exclusion' {
        $script:Variables = @([pscustomobject]@{ RowKey = 'backupapp'; Value = 'Backup, Inc'; VariableType = $null })
        $script:Apps = @((New-App 'Backup, Inc'), (New-App 'Kept'))

        $Prepared = Get-CIPPBaselineDisableInactiveAppsState -Item (New-AppsItem -Excluded '%backupapp%') -TenantFilter $script:Tenant

        @($Prepared.Current.offenders) | Should -Be @('Kept (app-Kept)')
    }

    It 'refuses to run when an exclusion variable is not defined for the tenant' {
        $script:Apps = @(New-App 'Protected')

        { Get-CIPPBaselineDisableInactiveAppsState -Item (New-AppsItem -Excluded '%missing%') -TenantFilter $script:Tenant } | Should -Throw '*%missing%*'
    }

    It 'refuses a window under 30 days' {
        $script:Apps = @(New-App 'Idle')

        { Get-CIPPBaselineDisableInactiveAppsState -Item (New-AppsItem -Days 29) -TenantFilter $script:Tenant } | Should -Throw '*30-day floor*'
    }
}

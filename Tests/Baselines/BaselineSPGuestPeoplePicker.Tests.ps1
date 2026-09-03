# SPGuestPeoplePicker covers the tenant default and every site collection from one SPOSites cache.
# The prepare hook derives offenders/targets from that cache (no live calls); the executor applies
# the value per target - tenant via Set-CIPPSPOTenant, sites via Set-CIPPSPOSite - tolerating partial
# failure but throwing when every write fails. Static counting mocks only.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines'

    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Get-CIPPSPOTenant { param($TenantFilter, [switch]$UseCertificate) }
    function Set-CIPPSPOTenant { [CmdletBinding()] param([Parameter(ValueFromPipeline)]$InputObject, $Properties, [switch]$UseCertificate) process {} }
    function Set-CIPPSPOSite { param($TenantFilter, $SiteUrl, $Properties, [switch]$UseCertificate) }
    function Set-CIPPDBCacheSPOSites { param($TenantFilter) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Write-Information { param($MessageData) }

    . (Join-Path $Baselines 'Get-CIPPBaselineSPGuestPeoplePickerState.ps1')
    . (Join-Path $Baselines 'Invoke-CIPPBaselineSPGuestPeoplePicker.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'

    function script:New-Row { param([string]$Scope, [string]$Url, [bool]$Show)
        [PSCustomObject]@{ id = ($Url ?? 'tenant-default'); Scope = $Scope; Url = $Url; ShowPeoplePickerSuggestionsForGuestUsers = $Show }
    }
    function script:New-Item2 { param([bool]$ShowGuests) [PSCustomObject]@{ Variables = [PSCustomObject]@{ showGuests = $ShowGuests } } }
}

Describe 'Get-CIPPBaselineSPGuestPeoplePickerState' {
    It 'flags the tenant default and sites that differ (wanted = show)' {
        Mock New-CIPPDbRequest {
            @(
                New-Row -Scope 'tenant' -Url $null -Show $false
                New-Row -Scope 'site' -Url 'https://c.sharepoint.com/sites/A' -Show $false
                New-Row -Scope 'site' -Url 'https://c.sharepoint.com/sites/B' -Show $true
            )
        }
        $p = Get-CIPPBaselineSPGuestPeoplePickerState -Item (New-Item2 -ShowGuests $true) -TenantFilter $script:Tenant
        @($p.Current.offenders) | Should -Be @('Tenant default', 'https://c.sharepoint.com/sites/A')
        @($p.Current.targets)[0].Scope | Should -Be 'tenant'
        @($p.Current.targets)[1].SiteUrl | Should -Be 'https://c.sharepoint.com/sites/A'
    }

    It 'flags only what differs (wanted = hide)' {
        Mock New-CIPPDbRequest {
            @(
                New-Row -Scope 'tenant' -Url $null -Show $false
                New-Row -Scope 'site' -Url 'https://c.sharepoint.com/sites/B' -Show $true
            )
        }
        $p = Get-CIPPBaselineSPGuestPeoplePickerState -Item (New-Item2 -ShowGuests $false) -TenantFilter $script:Tenant
        @($p.Current.offenders) | Should -Be @('https://c.sharepoint.com/sites/B')
    }

    It 'returns null Current on an empty cache so the engine collects on miss' {
        Mock New-CIPPDbRequest { @() }
        $p = Get-CIPPBaselineSPGuestPeoplePickerState -Item (New-Item2 -ShowGuests $true) -TenantFilter $script:Tenant
        $p.Current | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-CIPPBaselineSPGuestPeoplePicker' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Set-CIPPDBCacheSPOSites {}
        Mock Get-CIPPSPOTenant { [PSCustomObject]@{ _ObjectIdentity_ = 'id'; TenantFilter = $script:Tenant } }
        $script:Remediate = [PSCustomObject]@{ executor = 'SPGuestPeoplePicker'; useCertificate = $true; refreshCache = @('SPOSites') }
    }

    It 'writes the tenant default and each site, then refreshes the cache' {
        Mock Set-CIPPSPOTenant {}
        Mock Set-CIPPSPOSite {}
        $Current = [PSCustomObject]@{ targets = @(
                [PSCustomObject]@{ Scope = 'tenant'; SiteUrl = $null; Wanted = $true }
                [PSCustomObject]@{ Scope = 'site'; SiteUrl = 'https://c.sharepoint.com/sites/A'; Wanted = $true }
                [PSCustomObject]@{ Scope = 'site'; SiteUrl = 'https://c.sharepoint.com/sites/B'; Wanted = $true }
            ) }
        Invoke-CIPPBaselineSPGuestPeoplePicker -Remediate $script:Remediate -TenantFilter $script:Tenant -Current $Current
        Should -Invoke Set-CIPPSPOTenant -Times 1 -Exactly
        Should -Invoke Set-CIPPSPOSite -Times 2 -Exactly
        Should -Invoke Set-CIPPDBCacheSPOSites -Times 1 -Exactly
    }

    It 'tolerates a partial failure without throwing' {
        Mock Set-CIPPSPOTenant {}
        Mock Set-CIPPSPOSite { throw 'boom' } -ParameterFilter { $SiteUrl -eq 'https://c.sharepoint.com/sites/B' }
        Mock Set-CIPPSPOSite {} -ParameterFilter { $SiteUrl -eq 'https://c.sharepoint.com/sites/A' }
        $Current = [PSCustomObject]@{ targets = @(
                [PSCustomObject]@{ Scope = 'site'; SiteUrl = 'https://c.sharepoint.com/sites/A'; Wanted = $true }
                [PSCustomObject]@{ Scope = 'site'; SiteUrl = 'https://c.sharepoint.com/sites/B'; Wanted = $true }
            ) }
        { Invoke-CIPPBaselineSPGuestPeoplePicker -Remediate $script:Remediate -TenantFilter $script:Tenant -Current $Current } | Should -Not -Throw
    }

    It 'throws when every write fails' {
        Mock Set-CIPPSPOSite { throw 'denied' }
        $Current = [PSCustomObject]@{ targets = @([PSCustomObject]@{ Scope = 'site'; SiteUrl = 'https://c.sharepoint.com/sites/A'; Wanted = $true }) }
        { Invoke-CIPPBaselineSPGuestPeoplePicker -Remediate $script:Remediate -TenantFilter $script:Tenant -Current $Current } | Should -Throw
    }

    It 'does nothing when there are no targets' {
        Mock Set-CIPPSPOSite {}
        Mock Set-CIPPSPOTenant {}
        Invoke-CIPPBaselineSPGuestPeoplePicker -Remediate $script:Remediate -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ targets = @() })
        Should -Invoke Set-CIPPSPOSite -Times 0 -Exactly
    }
}

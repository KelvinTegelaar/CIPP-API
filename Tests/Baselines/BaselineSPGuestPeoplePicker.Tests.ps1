# SPGuestPeoplePicker covers the tenant default (from the SPOTenant cache) and every site collection
# (from the generic SPOSites cache). The prepare hook derives offenders/targets from those caches (no
# live calls); the executor applies the value per target - tenant via Set-CIPPSPOTenant, sites via
# Set-CIPPSPOSite - tolerating partial failure but throwing when every write fails. Static mocks only.

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

    function script:New-Site { param([string]$Url, [bool]$Show) [PSCustomObject]@{ id = $Url; Url = $Url; ShowPeoplePickerSuggestionsForGuestUsers = $Show } }
    function script:New-Item2 { param([bool]$ShowGuests) [PSCustomObject]@{ Variables = [PSCustomObject]@{ showGuests = $ShowGuests } } }
    function script:Set-TenantRows { param([Nullable[bool]]$Show)
        $script:TenantRows = if ($null -eq $Show) { @() } else { @([PSCustomObject]@{ ShowPeoplePickerSuggestionsForGuestUsers = $Show }) }
    }
}

Describe 'Get-CIPPBaselineSPGuestPeoplePickerState' {
    BeforeEach {
        # Static mocks answering per cache type; each It sets $script:TenantRows / $script:SiteRows.
        $script:TenantRows = @()
        $script:SiteRows = @()
        Mock New-CIPPDbRequest { $script:TenantRows } -ParameterFilter { $Type -eq 'SPOTenant' }
        Mock New-CIPPDbRequest { $script:SiteRows } -ParameterFilter { $Type -eq 'SPOSites' }
    }

    It 'flags the tenant default and sites that differ (wanted = show)' {
        Set-TenantRows $false
        $script:SiteRows = @((New-Site 'https://c.sharepoint.com/sites/A' $false), (New-Site 'https://c.sharepoint.com/sites/B' $true))
        $p = Get-CIPPBaselineSPGuestPeoplePickerState -Item (New-Item2 -ShowGuests $true) -TenantFilter $script:Tenant
        @($p.Current.offenders) | Should -Be @('Tenant default', 'https://c.sharepoint.com/sites/A')
        @($p.Current.targets)[0].Scope | Should -Be 'tenant'
        @($p.Current.targets)[1].SiteUrl | Should -Be 'https://c.sharepoint.com/sites/A'
    }

    It 'flags only what differs (wanted = hide)' {
        Set-TenantRows $false
        $script:SiteRows = @((New-Site 'https://c.sharepoint.com/sites/B' $true))
        $p = Get-CIPPBaselineSPGuestPeoplePickerState -Item (New-Item2 -ShowGuests $false) -TenantFilter $script:Tenant
        @($p.Current.offenders) | Should -Be @('https://c.sharepoint.com/sites/B')
    }

    It 'is compliant when the tenant default and every site already match' {
        Set-TenantRows $true
        $script:SiteRows = @((New-Site 'https://c.sharepoint.com/sites/A' $true))
        $p = Get-CIPPBaselineSPGuestPeoplePickerState -Item (New-Item2 -ShowGuests $true) -TenantFilter $script:Tenant
        @($p.Current.offenders) | Should -BeNullOrEmpty
    }

    It 'returns null Current when the SPOTenant cache is empty so the engine collects on miss' {
        Set-TenantRows $null
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

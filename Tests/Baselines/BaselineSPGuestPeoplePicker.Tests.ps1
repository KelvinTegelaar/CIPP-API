# SPGuestPeoplePicker reads LIVE (not cache): the prepare hook derives offenders/targets from
# Get-CIPPSPOTenant + Get-CIPPSPOSite, and the executor writes then re-reads AUTHORITATIVELY
# (Get-CIPPSPOTenant / Get-CIPPSPOSiteBulk single-site) to verify. Static counting mocks only.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines'

    function Get-CIPPSPOTenant { param($TenantFilter, [switch]$UseCertificate, [switch]$SkipCache) }
    function Get-CIPPSPOSite { param($TenantFilter, $SiteUrl, [switch]$UseCertificate) }
    function Set-CIPPSPOTenant { [CmdletBinding()] param([Parameter(ValueFromPipeline)]$InputObject, $Properties, [switch]$UseCertificate) process {} }
    function Set-CIPPSPOSiteBulk { param($TenantFilter, $Sites, $MaxConcurrency, $MaxRetries, [switch]$UseCertificate) }
    function Get-CIPPSPOSiteBulk { param($TenantFilter, $SiteUrls, $MaxConcurrency, $MaxRetries, [switch]$UseCertificate) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Write-Information { param($MessageData) }

    . (Join-Path $Baselines 'Get-CIPPBaselineSPGuestPeoplePickerState.ps1')
    . (Join-Path $Baselines 'Invoke-CIPPBaselineSPGuestPeoplePicker.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    function script:New-Site { param([string]$Url, [bool]$Show) [PSCustomObject]@{ Url = $Url; ShowPeoplePickerSuggestionsForGuestUsers = $Show } }
    function script:New-Item2 { param([bool]$ShowGuests) [PSCustomObject]@{ Variables = [PSCustomObject]@{ showGuests = $ShowGuests } } }
}

Describe 'Get-CIPPBaselineSPGuestPeoplePickerState' {
    It 'flags the tenant default and sites that differ (wanted = show)' {
        Mock Get-CIPPSPOTenant { [PSCustomObject]@{ ShowPeoplePickerSuggestionsForGuestUsers = $false } }
        Mock Get-CIPPSPOSite { @((New-Site 'https://c.sharepoint.com/sites/A' $false), (New-Site 'https://c.sharepoint.com/sites/B' $true)) }
        $p = Get-CIPPBaselineSPGuestPeoplePickerState -Item (New-Item2 -ShowGuests $true) -TenantFilter $script:Tenant
        @($p.Current.offenders) | Should -Be @('Tenant default', 'https://c.sharepoint.com/sites/A')
        @($p.Current.targets)[0].Scope | Should -Be 'tenant'
        @($p.Current.targets)[1].SiteUrl | Should -Be 'https://c.sharepoint.com/sites/A'
    }

    It 'flags only what differs (wanted = hide)' {
        Mock Get-CIPPSPOTenant { [PSCustomObject]@{ ShowPeoplePickerSuggestionsForGuestUsers = $false } }
        Mock Get-CIPPSPOSite { @((New-Site 'https://c.sharepoint.com/sites/B' $true)) }
        $p = Get-CIPPBaselineSPGuestPeoplePickerState -Item (New-Item2 -ShowGuests $false) -TenantFilter $script:Tenant
        @($p.Current.offenders) | Should -Be @('https://c.sharepoint.com/sites/B')
    }

    It 'is compliant when the tenant default and every site already match' {
        Mock Get-CIPPSPOTenant { [PSCustomObject]@{ ShowPeoplePickerSuggestionsForGuestUsers = $true } }
        Mock Get-CIPPSPOSite { @((New-Site 'https://c.sharepoint.com/sites/A' $true)) }
        $p = Get-CIPPBaselineSPGuestPeoplePickerState -Item (New-Item2 -ShowGuests $true) -TenantFilter $script:Tenant
        @($p.Current.offenders) | Should -BeNullOrEmpty
    }

    It 'returns null Current when the live tenant read fails' {
        Mock Get-CIPPSPOTenant { $null }
        Mock Get-CIPPSPOSite { @() }
        $p = Get-CIPPBaselineSPGuestPeoplePickerState -Item (New-Item2 -ShowGuests $true) -TenantFilter $script:Tenant
        $p.Current | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-CIPPBaselineSPGuestPeoplePicker' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Get-CIPPSPOTenant { [PSCustomObject]@{ _ObjectIdentity_ = 'id'; TenantFilter = $script:Tenant; ShowPeoplePickerSuggestionsForGuestUsers = $true } }
        Mock Set-CIPPSPOTenant {}
        $script:Remediate = [PSCustomObject]@{ executor = 'SPGuestPeoplePicker'; useCertificate = $true }
    }

    It 'writes the tenant default and sites, then verifies via authoritative re-read' {
        Mock Set-CIPPSPOSiteBulk { @(
                [PSCustomObject]@{ SiteUrl = 'https://c.sharepoint.com/sites/A'; Success = $true; Error = $null }
                [PSCustomObject]@{ SiteUrl = 'https://c.sharepoint.com/sites/B'; Success = $true; Error = $null }
            ) }
        Mock Get-CIPPSPOSiteBulk { @(
                [PSCustomObject]@{ SiteUrl = 'https://c.sharepoint.com/sites/A'; Site = [PSCustomObject]@{ ShowPeoplePickerSuggestionsForGuestUsers = $true }; Success = $true; Error = $null }
                [PSCustomObject]@{ SiteUrl = 'https://c.sharepoint.com/sites/B'; Site = [PSCustomObject]@{ ShowPeoplePickerSuggestionsForGuestUsers = $true }; Success = $true; Error = $null }
            ) }
        $Current = [PSCustomObject]@{ targets = @(
                [PSCustomObject]@{ Scope = 'tenant'; SiteUrl = $null; Wanted = $true }
                [PSCustomObject]@{ Scope = 'site'; SiteUrl = 'https://c.sharepoint.com/sites/A'; Wanted = $true }
                [PSCustomObject]@{ Scope = 'site'; SiteUrl = 'https://c.sharepoint.com/sites/B'; Wanted = $true }
            ) }
        Invoke-CIPPBaselineSPGuestPeoplePicker -Remediate $script:Remediate -TenantFilter $script:Tenant -Current $Current
        Should -Invoke Set-CIPPSPOTenant -Times 1 -Exactly
        Should -Invoke Set-CIPPSPOSiteBulk -Times 1 -Exactly
        Should -Invoke Get-CIPPSPOSiteBulk -Times 1 -Exactly
    }

    It 'tolerates a verify failure (value did not change) without throwing' {
        Mock Set-CIPPSPOSiteBulk { @(
                [PSCustomObject]@{ SiteUrl = 'https://c.sharepoint.com/sites/A'; Success = $true; Error = $null }
                [PSCustomObject]@{ SiteUrl = 'https://c.sharepoint.com/sites/B'; Success = $true; Error = $null }
            ) }
        Mock Get-CIPPSPOSiteBulk { @(
                [PSCustomObject]@{ SiteUrl = 'https://c.sharepoint.com/sites/A'; Site = [PSCustomObject]@{ ShowPeoplePickerSuggestionsForGuestUsers = $true }; Success = $true; Error = $null }
                [PSCustomObject]@{ SiteUrl = 'https://c.sharepoint.com/sites/B'; Site = [PSCustomObject]@{ ShowPeoplePickerSuggestionsForGuestUsers = $false }; Success = $true; Error = $null }
            ) }
        $Current = [PSCustomObject]@{ targets = @(
                [PSCustomObject]@{ Scope = 'site'; SiteUrl = 'https://c.sharepoint.com/sites/A'; Wanted = $true }
                [PSCustomObject]@{ Scope = 'site'; SiteUrl = 'https://c.sharepoint.com/sites/B'; Wanted = $true }
            ) }
        { Invoke-CIPPBaselineSPGuestPeoplePicker -Remediate $script:Remediate -TenantFilter $script:Tenant -Current $Current } | Should -Not -Throw
    }

    It 'throws when the whole site write batch fails' {
        Mock Set-CIPPSPOSiteBulk { throw 'denied' }
        Mock Get-CIPPSPOSiteBulk { @() }
        $Current = [PSCustomObject]@{ targets = @([PSCustomObject]@{ Scope = 'site'; SiteUrl = 'https://c.sharepoint.com/sites/A'; Wanted = $true }) }
        { Invoke-CIPPBaselineSPGuestPeoplePicker -Remediate $script:Remediate -TenantFilter $script:Tenant -Current $Current } | Should -Throw
    }

    It 'does nothing when there are no targets' {
        Mock Set-CIPPSPOSiteBulk {}
        Mock Get-CIPPSPOSiteBulk {}
        Invoke-CIPPBaselineSPGuestPeoplePicker -Remediate $script:Remediate -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ targets = @() })
        Should -Invoke Set-CIPPSPOSiteBulk -Times 0 -Exactly
    }
}

# SPGuestPeoplePicker reads from cache: the prepare hook derives offenders/targets from
# Get-CIPPSPOTenant (the tenant default, 1h-cached) + the SPOSites reporting cache (New-CIPPDbRequest),
# and the executor writes then stops - the next daily cache read verifies. The write sweep is guarded to
# once per 24h per tenant by Test-CIPPRerun. Static counting mocks only.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines'

    function Get-CIPPSPOTenant { param($TenantFilter, [switch]$UseCertificate, [switch]$SkipCache) }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Set-CIPPSPOTenant { [CmdletBinding()] param([Parameter(ValueFromPipeline)]$InputObject, $Properties, [switch]$UseCertificate) process {} }
    function Set-CIPPSPOSiteBulk { param($TenantFilter, $Sites, $MaxConcurrency, $MaxRetries, [switch]$UseCertificate) }
    function Test-CIPPRerun { param($TenantFilter, $API, [int64]$Interval) }
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
        Mock New-CIPPDbRequest { @((New-Site 'https://c.sharepoint.com/sites/A' $false), (New-Site 'https://c.sharepoint.com/sites/B' $true)) }
        $p = Get-CIPPBaselineSPGuestPeoplePickerState -Item (New-Item2 -ShowGuests $true) -TenantFilter $script:Tenant
        @($p.Current.offenders) | Should -Be @('Tenant default', 'https://c.sharepoint.com/sites/A')
        @($p.Current.targets)[0].Scope | Should -Be 'tenant'
        @($p.Current.targets)[1].SiteUrl | Should -Be 'https://c.sharepoint.com/sites/A'
    }

    It 'flags only what differs (wanted = hide)' {
        Mock Get-CIPPSPOTenant { [PSCustomObject]@{ ShowPeoplePickerSuggestionsForGuestUsers = $false } }
        Mock New-CIPPDbRequest { @((New-Site 'https://c.sharepoint.com/sites/B' $true)) }
        $p = Get-CIPPBaselineSPGuestPeoplePickerState -Item (New-Item2 -ShowGuests $false) -TenantFilter $script:Tenant
        @($p.Current.offenders) | Should -Be @('https://c.sharepoint.com/sites/B')
    }

    It 'is compliant when the tenant default and every cached site already match' {
        Mock Get-CIPPSPOTenant { [PSCustomObject]@{ ShowPeoplePickerSuggestionsForGuestUsers = $true } }
        Mock New-CIPPDbRequest { @((New-Site 'https://c.sharepoint.com/sites/A' $true)) }
        $p = Get-CIPPBaselineSPGuestPeoplePickerState -Item (New-Item2 -ShowGuests $true) -TenantFilter $script:Tenant
        @($p.Current.offenders) | Should -BeNullOrEmpty
    }

    It 'returns null Current when the tenant read fails' {
        Mock Get-CIPPSPOTenant { throw 'SharePoint admin access denied' }
        Mock New-CIPPDbRequest { @() }
        $p = Get-CIPPBaselineSPGuestPeoplePickerState -Item (New-Item2 -ShowGuests $true) -TenantFilter $script:Tenant
        $p.Current | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-CIPPBaselineSPGuestPeoplePicker' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Test-CIPPRerun { $false }
        Mock Get-CIPPSPOTenant { [PSCustomObject]@{ _ObjectIdentity_ = 'id'; TenantFilter = $script:Tenant; ShowPeoplePickerSuggestionsForGuestUsers = $true } }
        Mock Set-CIPPSPOTenant {}
        $script:Remediate = [PSCustomObject]@{ executor = 'SPGuestPeoplePicker'; useCertificate = $true }
    }

    It 'writes the tenant default and sites, without a verification re-read' {
        Mock Set-CIPPSPOSiteBulk { @(
                [PSCustomObject]@{ SiteUrl = 'https://c.sharepoint.com/sites/A'; Success = $true; Error = $null }
                [PSCustomObject]@{ SiteUrl = 'https://c.sharepoint.com/sites/B'; Success = $true; Error = $null }
            ) }
        $Current = [PSCustomObject]@{ targets = @(
                [PSCustomObject]@{ Scope = 'tenant'; SiteUrl = $null; Wanted = $true }
                [PSCustomObject]@{ Scope = 'site'; SiteUrl = 'https://c.sharepoint.com/sites/A'; Wanted = $true }
                [PSCustomObject]@{ Scope = 'site'; SiteUrl = 'https://c.sharepoint.com/sites/B'; Wanted = $true }
            ) }
        Invoke-CIPPBaselineSPGuestPeoplePicker -Remediate $script:Remediate -TenantFilter $script:Tenant -Current $Current
        Should -Invoke Set-CIPPSPOTenant -Times 1 -Exactly
        Should -Invoke Set-CIPPSPOSiteBulk -Times 1 -Exactly
    }

    It 'skips the write sweep entirely inside the 24h rerun guard' {
        Mock Test-CIPPRerun { $true }
        Mock Set-CIPPSPOSiteBulk {}
        $Current = [PSCustomObject]@{ targets = @(
                [PSCustomObject]@{ Scope = 'tenant'; SiteUrl = $null; Wanted = $true }
                [PSCustomObject]@{ Scope = 'site'; SiteUrl = 'https://c.sharepoint.com/sites/A'; Wanted = $true }
            ) }
        Invoke-CIPPBaselineSPGuestPeoplePicker -Remediate $script:Remediate -TenantFilter $script:Tenant -Current $Current
        Should -Invoke Set-CIPPSPOTenant -Times 0 -Exactly
        Should -Invoke Set-CIPPSPOSiteBulk -Times 0 -Exactly
    }

    It 'tolerates a per-site failure without throwing' {
        Mock Set-CIPPSPOSiteBulk { @(
                [PSCustomObject]@{ SiteUrl = 'https://c.sharepoint.com/sites/A'; Success = $true; Error = $null }
                [PSCustomObject]@{ SiteUrl = 'https://c.sharepoint.com/sites/B'; Success = $false; Error = 'denied' }
            ) }
        $Current = [PSCustomObject]@{ targets = @(
                [PSCustomObject]@{ Scope = 'site'; SiteUrl = 'https://c.sharepoint.com/sites/A'; Wanted = $true }
                [PSCustomObject]@{ Scope = 'site'; SiteUrl = 'https://c.sharepoint.com/sites/B'; Wanted = $true }
            ) }
        { Invoke-CIPPBaselineSPGuestPeoplePicker -Remediate $script:Remediate -TenantFilter $script:Tenant -Current $Current } | Should -Not -Throw
    }

    It 'throws when the whole site write batch fails' {
        Mock Set-CIPPSPOSiteBulk { throw 'denied' }
        $Current = [PSCustomObject]@{ targets = @([PSCustomObject]@{ Scope = 'site'; SiteUrl = 'https://c.sharepoint.com/sites/A'; Wanted = $true }) }
        { Invoke-CIPPBaselineSPGuestPeoplePicker -Remediate $script:Remediate -TenantFilter $script:Tenant -Current $Current } | Should -Throw
    }

    It 'does nothing when there are no targets' {
        Mock Set-CIPPSPOSiteBulk {}
        Invoke-CIPPBaselineSPGuestPeoplePicker -Remediate $script:Remediate -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ targets = @() })
        Should -Invoke Set-CIPPSPOSiteBulk -Times 0 -Exactly
        Should -Invoke Test-CIPPRerun -Times 0 -Exactly
    }
}

# Pester tests for Invoke-CIPPStandardSPGuestPeoplePicker
#
# SharePoint refuses ShowPeoplePickerSuggestionsForGuestUsers on the My Site host and on PointPublishing
# (/portals/hub, /portals/Community) site collections, so those sites must never be counted or written.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPStandards/Public/Standards/Invoke-CIPPStandardSPGuestPeoplePicker.ps1')

    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) $true }
    function Get-CIPPSPOTenant { [CmdletBinding()] param($TenantFilter, [switch]$UseCertificate) }
    function Set-CIPPSPOTenant { [CmdletBinding()] param([Parameter(ValueFromPipeline)]$InputObject, $Properties, [switch]$UseCertificate) process {} }
    function Set-CIPPSPOSiteBulk { [CmdletBinding()] param($TenantFilter, $Sites, [switch]$UseCertificate) }
    function New-CIPPDbRequest { [CmdletBinding()] param($TenantFilter, $Type) }
    function Test-CIPPRerun { [CmdletBinding()] param($Tenant, $API, $Interval) $false }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $Tenant) }

    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Invoke-CIPPStandardSPGuestPeoplePicker' {
    BeforeEach {
        Mock Get-CIPPSPOTenant { [PSCustomObject]@{ ShowPeoplePickerSuggestionsForGuestUsers = $true } }
        Mock New-CIPPDbRequest { @(
                [PSCustomObject]@{ Url = 'https://c-my.sharepoint.com/'; Template = 'SPSMSITEHOST#0'; ShowPeoplePickerSuggestionsForGuestUsers = $false }
                [PSCustomObject]@{ Url = 'https://c.sharepoint.com/portals/hub'; Template = 'POINTPUBLISHINGHUB#0'; ShowPeoplePickerSuggestionsForGuestUsers = $false }
                [PSCustomObject]@{ Url = 'https://c.sharepoint.com/portals/Community'; Template = 'POINTPUBLISHINGTOPIC#0'; ShowPeoplePickerSuggestionsForGuestUsers = $false }
                [PSCustomObject]@{ Url = 'https://c.sharepoint.com/sites/Renamed'; Template = 'REDIRECTSITE#0'; ShowPeoplePickerSuggestionsForGuestUsers = $false }
                [PSCustomObject]@{ Url = 'http://bot190434-002/sites/83cccd11-2eb6-4db6-9fef-6d0ac592e605'; Template = 'STS#-1'; ShowPeoplePickerSuggestionsForGuestUsers = $false }
                [PSCustomObject]@{ Url = 'https://c.sharepoint.com/sites/A'; Template = 'GROUP#0'; ShowPeoplePickerSuggestionsForGuestUsers = $false }
            ) }
        Mock Set-CIPPSPOSiteBulk { foreach ($Site in $Sites) { [PSCustomObject]@{ SiteUrl = $Site.SiteUrl; Success = $true } } }
        Mock Set-CIPPStandardsCompareField {}
    }

    It 'writes only sites SharePoint accepts the setting on' {
        Invoke-CIPPStandardSPGuestPeoplePicker -Tenant $script:Tenant -Settings ([PSCustomObject]@{ state = 'true'; remediate = $true })

        Should -Invoke Set-CIPPSPOSiteBulk -Times 1 -Exactly -ParameterFilter { @($Sites.SiteUrl) -join ',' -eq 'https://c.sharepoint.com/sites/A' }
    }

    It 'reports only those sites as non-compliant' {
        Invoke-CIPPStandardSPGuestPeoplePicker -Tenant $script:Tenant -Settings ([PSCustomObject]@{ state = 'true'; report = $true })

        Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter { $CurrentValue.NonCompliantSiteCount -eq 1 }
    }
}

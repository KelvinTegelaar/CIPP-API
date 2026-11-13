# Pester tests for Invoke-CIPPStandardPhishSimSpoofIntelligence
#
# The spoof list holds Allow and Block entries, one per spoof type. The standard used to look at the
# sending domain only, so a Block entry counted as the domain being allowed, and "remove extra
# domains" deleted Block entries an admin had added.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardPhishSimSpoofIntelligence.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardPhishSimSpoofIntelligence.ps1 under Modules/' }

    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function New-ExoRequest { [CmdletBinding()] param($tenantid, $cmdlet, $cmdParams) }
    function New-ExoBulkRequest { [CmdletBinding()] param($tenantid, $cmdletArray) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $TenantFilter, $Tenant) }
    function Get-NormalizedError { [CmdletBinding()] param($Message) $Message }

    . $StandardPath
    $script:Tenant = 'contoso.onmicrosoft.com'

    function script:New-SpoofItem {
        param($Id, $Domain, $Action = 'Allow', $SpoofType = 'Internal')
        [PSCustomObject]@{ Identity = $Id; SendingInfrastructure = $Domain; SpoofedUser = '*'; SpoofType = $SpoofType; Action = $Action }
    }
}

Describe 'Invoke-CIPPStandardPhishSimSpoofIntelligence' {
    BeforeEach {
        $script:Bulk = @()
        Mock Test-CIPPStandardLicense { $true }
        Mock New-ExoRequest { $script:Items }
        Mock New-ExoBulkRequest { $script:Bulk = @($cmdletArray.CmdletInput); @() }
        Mock Write-LogMessage { }
        Mock Write-StandardsAlert { }
        Mock Set-CIPPStandardsCompareField { }
        $script:Settings = @{ AllowedDomains = @([PSCustomObject]@{ value = 'phish.example' }); remediate = $true; alert = $true; report = $true }
    }

    It 'is compliant when the domain is allowed for both spoof types' {
        $script:Items = @((New-SpoofItem 1 'phish.example' -SpoofType Internal), (New-SpoofItem 2 'phish.example' -SpoofType External))

        Invoke-CIPPStandardPhishSimSpoofIntelligence -Tenant $script:Tenant -Settings $script:Settings

        Should -Invoke New-ExoBulkRequest -Times 0 -Exactly
        Should -Invoke Write-StandardsAlert -Times 0 -Exactly
        Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter { $CurrentValue.IsCompliant -eq $true -and (@($CurrentValue.AllowedDomains) -join ',') -eq 'phish.example' }
    }

    It 'does not count a Block entry as the domain being allowed' {
        $script:Items = @((New-SpoofItem 1 'phish.example' -Action Block -SpoofType Internal), (New-SpoofItem 2 'phish.example' -Action Block -SpoofType External))

        Invoke-CIPPStandardPhishSimSpoofIntelligence -Tenant $script:Tenant -Settings $script:Settings

        Should -Invoke Write-StandardsAlert -Times 1 -Exactly
        @($script:Bulk | Where-Object CmdletName -EQ 'New-TenantAllowBlockListSpoofItems').Count | Should -Be 2
        Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter { $CurrentValue.IsCompliant -eq $false -and @($CurrentValue.AllowedDomains).Count -eq 0 }
    }

    It 'adds only the missing spoof type when one is already allowed' {
        $script:Items = @((New-SpoofItem 1 'phish.example' -SpoofType Internal))

        Invoke-CIPPStandardPhishSimSpoofIntelligence -Tenant $script:Tenant -Settings $script:Settings

        $Added = @($script:Bulk | Where-Object CmdletName -EQ 'New-TenantAllowBlockListSpoofItems')
        $Added.Count | Should -Be 1
        $Added[0].Parameters.SpoofType | Should -Be 'External'
        $Added[0].Parameters.Action | Should -Be 'Allow'
    }

    It 'removes extra Allow entries but never Block entries' {
        $script:Items = @(
            (New-SpoofItem 1 'phish.example' -SpoofType Internal), (New-SpoofItem 2 'phish.example' -SpoofType External),
            (New-SpoofItem 3 'old-vendor.example'), (New-SpoofItem 4 'attacker.example' -Action Block)
        )
        $script:Settings.RemoveExtraDomains = $true

        Invoke-CIPPStandardPhishSimSpoofIntelligence -Tenant $script:Tenant -Settings $script:Settings

        $Removed = @($script:Bulk | Where-Object CmdletName -EQ 'Remove-TenantAllowBlockListSpoofItems')
        $Removed.Count | Should -Be 1
        @($Removed[0].Parameters.Ids) | Should -Be @(3)
    }
}

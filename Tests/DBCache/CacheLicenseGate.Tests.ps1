BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) }
    function Set-CIPPDBCacheExoTransportRules { param($TenantFilter, $QueueId) }
    function Set-CIPPDBCacheUsers { param($TenantFilter, $QueueId) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPDBCacheSchedule.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/Push-CIPPDBCacheData.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/CIPPDBCache/Push-ExecCIPPDBCache.ps1')
}

Describe 'Push-CIPPDBCacheData' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Test-CIPPStandardLicense { $Preset -ne 'Exchange' }
    }

    It 'drops every Exchange task when the tenant has no Exchange license, checking each preset once' {
        $Tasks = Push-CIPPDBCacheData -Item @{ TenantFilter = 'contoso.com'; QueueId = 'q' }
        $Names = @($Tasks | ForEach-Object { $_.CollectionType ?? $_.Name })

        $Names | Should -Not -Contain 'ExchangeConfig'
        $Names | Should -Not -Contain 'ExchangeData'
        $Names | Should -Not -Contain 'Mailboxes'
        $Names[0..2] | Should -Be @('CopilotUsage', 'Graph', 'MFAState')
        ($Tasks | Where-Object Name -EQ 'SPOSites').QueueName | Should -Be 'DB Cache SPOSites - contoso.com'
        Should -Invoke Test-CIPPStandardLicense -Times 1 -Exactly -ParameterFilter { $Preset -eq 'SharePoint' }
    }
}

Describe 'Push-ExecCIPPDBCache single type' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Set-CIPPDBCacheExoTransportRules {}
        Mock Set-CIPPDBCacheUsers {}
        Mock Test-CIPPStandardLicense { $false }
    }

    It 'skips a type in a licensed group when the tenant lacks that license' {
        $Result = Push-ExecCIPPDBCache -Item @{ Name = 'ExoTransportRules'; TenantFilter = 'contoso.com' }

        $Result | Should -BeLike 'Skipped ExoTransportRules*no Exchange license'
        Should -Invoke Set-CIPPDBCacheExoTransportRules -Times 0
    }

    It 'runs a type that needs no license without checking' {
        Push-ExecCIPPDBCache -Item @{ Name = 'Users'; TenantFilter = 'contoso.com' } | Should -BeLike 'Successfully*'

        Should -Invoke Set-CIPPDBCacheUsers -Times 1
        Should -Invoke Test-CIPPStandardLicense -Times 0
    }
}

Describe 'Get-CIPPDBCacheSchedule Global Secure Access' {
    It 'collects both Global Secure Access caches nightly with the Entra ID P1 group' {
        $Schedule = Get-CIPPDBCacheSchedule
        $Schedule.ConditionalAccess.License | Should -Be 'Entra'
        $Schedule.ConditionalAccess.Types | Should -Contain 'NetworkAccess'
        $Schedule.ConditionalAccess.Types | Should -Contain 'NetworkAccessFiltering'
    }
}

# Pester tests for the breach alert. Write-AlertTrace resolves anything a run does not hand it and
# reopens (and re-notifies) it when it comes back, so every run must pass the full breach list and
# each breach must keep its identity when the feed edits its text.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-BreachInfo { param($TenantFilter, $Domain) }
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Get-CippException { param($Exception) }
    function Write-AlertMessage { param($tenant, $message) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-AlertContentHash.ps1')
    . (Join-Path $RepoRoot 'Modules/CippExtensions/Public/HIBP/New-BreachTenantSearch.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CippAlertBreachAlert.ps1')

    # Shape of one geoipdb /api/Breach?func=domain row: one row per address per breach
    function New-BreachRow {
        param($Email, $Source, $Date, $Description = 'A breach happened.')
        [pscustomobject]@{
            email        = $Email
            has_password = $false
            sources      = $Source
            Name         = $Email
            Title        = $Email
            Description  = $Description
            Date         = $Date
            Domain       = $Source.ToLowerInvariant()
            DataClasses  = @('Email addresses', 'Names')
            IsVerified   = $true
            LogoPath     = "https://logos.haveibeenpwned.com/$Source.png"
            clientDomain = 'contoso.com'
        }
    }
}

Describe 'Breach alert' {
    BeforeEach {
        $script:Captured = $null
        $script:Traced = 0
        $script:StoredSum = $null
        Mock Get-CIPPTable { @{} }
        Mock Get-CIPPAzDataTableEntity { if ($null -ne $script:StoredSum) { [pscustomobject]@{ sum = $script:StoredSum } } }
        Mock Add-CIPPAzDataTableEntity {}
        Mock Write-AlertMessage {}
        Mock Write-AlertTrace {
            param($cmdletName, $tenantFilter, $data)
            $script:Traced++
            $script:Captured = @($data | Where-Object { $null -ne $_ })
        }
        $script:Feed = @(
            New-BreachRow -Email 'adele@contoso.com' -Source 'Odido.nl' -Date '2026-02-12'
            New-BreachRow -Email 'adele@contoso.com' -Source 'Last.fm' -Date '2012-03-22'
        )
        Mock Get-BreachInfo { $script:Feed }
    }

    It 'still hands over every breach when the count has not changed since the last run' {
        Get-CippAlertBreachAlert -TenantFilter 'contoso.onmicrosoft.com'
        $script:Captured.Count | Should -Be 2

        $script:StoredSum = 2
        Get-CippAlertBreachAlert -TenantFilter 'contoso.onmicrosoft.com'
        $script:Traced | Should -Be 2
        $script:Captured.Count | Should -Be 2
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly
    }

    It 'keys each breach on address, breach and date, so feed text edits keep the same identity' {
        Get-CippAlertBreachAlert -TenantFilter 'contoso.onmicrosoft.com'
        $First = @($script:Captured | ForEach-Object { (Get-AlertContentHash -AlertItem $_).ContentHash })

        $script:Feed = @(
            New-BreachRow -Email 'adele@contoso.com' -Source 'Odido.nl' -Date '2026-02-12' -Description 'Updated wording.'
            New-BreachRow -Email 'adele@contoso.com' -Source 'Last.fm' -Date '2012-03-22' -Description 'Updated wording.'
        )
        Get-CippAlertBreachAlert -TenantFilter 'contoso.onmicrosoft.com'
        $Second = @($script:Captured | ForEach-Object { (Get-AlertContentHash -AlertItem $_).ContentHash })

        (Get-AlertContentHash -AlertItem $script:Captured[0]).KeyField | Should -Be 'Id'
        $First[0] | Should -Not -Be $First[1]
        $Second | Should -Be $First
        $script:Captured[0].Message | Should -Be 'adele@contoso.com was found in the Odido.nl breach (2026-02-12)'
    }

    It 'reports an empty run when the feed has no breaches, so open items resolve' {
        $script:Feed = @()
        Get-CippAlertBreachAlert -TenantFilter 'contoso.onmicrosoft.com'
        $script:Traced | Should -Be 1
        $script:Captured.Count | Should -Be 0
    }

    It 'does not report a run when the feed lookup fails' {
        Mock Get-BreachInfo { throw 'geoipdb unavailable' }
        Get-CippAlertBreachAlert -TenantFilter 'contoso.onmicrosoft.com'
        $script:Traced | Should -Be 0
        Should -Invoke Write-AlertMessage -Times 1 -Exactly
    }
}

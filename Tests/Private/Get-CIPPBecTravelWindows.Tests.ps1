BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-Tenants { param($TenantFilter) [pscustomobject]@{ defaultDomainName = 'contoso.com'; initialDomainName = 'contoso.onmicrosoft.com'; customerId = 'c0ffee00-0000-0000-0000-000000000001' } }
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) $script:Tasks }
    foreach ($File in @('BEC/New-CIPPBecCollectorResult.ps1', 'BEC/Get-CIPPBecTravelWindows.ps1', 'BEC/Find-CIPPBecApprovedTravel.ps1')) {
        . (Join-Path $RepoRoot "Modules/CIPPCore/Public/$File")
    }
    $Epoch = { param($When) [string]([DateTimeOffset]::Parse($When)).ToUnixTimeSeconds() }
    $Name = 'Travel Policy victim@contoso.com - 2026-09-18 - 2026-09-25'
    $script:Tasks = @(
        [pscustomobject]@{ Tenant = 'contoso.onmicrosoft.com'; Command = 'New-CIPPTravelPolicy'; ScheduledTime = (& $Epoch '2026-09-18T00:00:00Z'); Parameters = (@{ Users = @('Victim@contoso.com'); Countries = @('es', 'PT'); PolicyName = $Name } | ConvertTo-Json -Compress) }
        [pscustomobject]@{ Tenant = 'contoso.onmicrosoft.com'; Command = 'Remove-CIPPTravelPolicy'; ScheduledTime = (& $Epoch '2026-09-25T00:00:00Z'); Parameters = (@{ PolicyName = $Name } | ConvertTo-Json -Compress) }
        # a colleague's trip, and a trip in another tenant
        [pscustomobject]@{ Tenant = 'contoso.com'; Command = 'New-CIPPTravelPolicy'; ScheduledTime = (& $Epoch '2026-09-18T00:00:00Z'); Parameters = (@{ Users = @('other@contoso.com'); Countries = @('US'); PolicyName = 'Travel Policy other@contoso.com - 2026-09-18 - 2026-09-20' } | ConvertTo-Json -Compress) }
        [pscustomobject]@{ Tenant = 'fabrikam.com'; Command = 'New-CIPPTravelPolicy'; ScheduledTime = (& $Epoch '2026-09-18T00:00:00Z'); Parameters = (@{ Users = @('victim@contoso.com'); Countries = @('BR'); PolicyName = 'Travel Policy victim@contoso.com - 2026-09-18 - 2026-09-20' } | ConvertTo-Json -Compress) }
    )
}

Describe 'Get-CIPPBecTravelWindows' {
    It 'reads the trips of this user in this tenant, whichever tenant identifier the task was stored under' {
        $Trips = @((Get-CIPPBecTravelWindows -TenantFilter 'contoso.com' -UserId 'u1' -UserPrincipalName 'victim@contoso.com').Data)
        $Trips.Count | Should -Be 1
        $Trips[0].Countries | Should -Be @('ES', 'PT')
        $Trips[0].Start | Should -Be '2026-09-18T00:00:00Z'
        $Trips[0].End | Should -Be '2026-09-25T00:00:00Z'
    }

    It 'ends a trip whose remove task is gone on the date in its name' {
        $Saved = $script:Tasks
        $script:Tasks = @($Saved | Where-Object Command -EQ 'New-CIPPTravelPolicy')
        try {
            $Trip = @((Get-CIPPBecTravelWindows -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com').Data)[0]
            $Trip.End | Should -Be '2026-09-26T00:00:00Z'
        } finally { $script:Tasks = $Saved }
    }
}

Describe 'Find-CIPPBecApprovedTravel' {
    It 'matches a country on the trip only while the trip lasts' {
        $Trips = @([pscustomobject]@{ PolicyName = 'Trip'; Countries = @('ES'); Start = '2026-09-18T00:00:00Z'; End = '2026-09-25T00:00:00Z' })
        (Find-CIPPBecApprovedTravel -TravelWindows $Trips -Country 'ES' -When '2026-09-20T10:00:00Z').PolicyName | Should -Be 'Trip'
        Find-CIPPBecApprovedTravel -TravelWindows $Trips -Country 'ES' -When '2026-09-26T10:00:00Z' | Should -BeNullOrEmpty
        Find-CIPPBecApprovedTravel -TravelWindows $Trips -Country 'FR' -When '2026-09-20T10:00:00Z' | Should -BeNullOrEmpty
    }
}

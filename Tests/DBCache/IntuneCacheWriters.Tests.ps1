# Each Intune cache type has one nightly writer, and every report page's Sync names a collector that exists.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:DBCacheRoot = Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache'
    $script:Collectors = Get-ChildItem $script:DBCacheRoot -Filter 'Set-CIPPDBCache*.ps1'
    $script:PagesRoot = Join-Path (Split-Path -Parent $RepoRoot) 'frontend/src/pages'
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntunePolicyListDefinitions.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPDBCacheSchedule.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Invoke-CIPPDBCacheCollection.ps1')
    foreach ($Name in 'IntunePolicyGroups', 'IntuneApplications', 'IntuneAppProtectionPolicies', 'IntuneScripts') {
        . (Join-Path $script:DBCacheRoot "Set-CIPPDBCache$Name.ps1")
    }

    function Test-CIPPStandardLicense { $true }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) }
    function Add-CIPPDbItem {
        param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty)
        $script:Written.Add([pscustomobject]@{ Type = $Type; Count = @($Data).Count; ClearOnEmpty = $ClearOnEmpty.IsPresent })
    }
    function New-GraphGetRequest {
        param($uri, $tenantid)
        $script:Requests.Add($uri)
        if ($script:GraphFails) { throw 'Graph is down' }
        [pscustomobject]@{ id = 'g1'; displayName = 'Group One' }
    }
    function New-GraphBulkRequest {
        param($Requests, $tenantid)
        foreach ($Request in @($Requests)) {
            $script:Requests.Add($Request.url)
            [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{ value = @() } }
        }
    }
}

Describe 'Intune cache writers' {
    BeforeEach {
        $script:Written = [System.Collections.Generic.List[object]]::new()
        $script:Requests = [System.Collections.Generic.List[string]]::new()
        $script:GraphFails = $false
    }

    It 'writes IntuneDeviceCompliancePolicies and its device statuses only from the IntunePolicies umbrella' {
        $Definition = @(Get-CIPPIntunePolicyListDefinitions).Where({ $_.CacheType -eq 'IntuneDeviceCompliancePolicies' })[0]
        $Definition.FetchDeviceStatuses | Should -BeTrue
        @($script:Collectors | Where-Object { (Get-Content $_.FullName -Raw) -match "'IntuneDeviceCompliancePolicies'" }).Name | Should -BeNullOrEmpty
        (Get-CIPPDBCacheSchedule).Intune.Types | Should -Contain 'IntunePolicies'
    }

    It 'keeps one Intune group-name snapshot, IntunePolicyGroups' {
        $Types = foreach ($Collector in $script:Collectors) {
            foreach ($Match in [regex]::Matches((Get-Content $Collector.FullName -Raw), "'(Intune[A-Za-z]*Groups)'")) { $Match.Groups[1].Value }
        }
        $Types | Sort-Object -Unique | Should -Be 'IntunePolicyGroups'
    }

    It 'refreshes the snapshot from <Collector> run on its own, and not when told to skip it' -ForEach @(
        @{ Collector = 'Set-CIPPDBCacheIntuneApplications' }
        @{ Collector = 'Set-CIPPDBCacheIntuneAppProtectionPolicies' }
        @{ Collector = 'Set-CIPPDBCacheIntuneScripts' }
    ) {
        & $Collector -TenantFilter 'contoso.com'
        @($script:Requests | Where-Object { $_ -match '/groups\?' }).Count | Should -Be 1
        @($script:Written | Where-Object Type -Like '*Groups').Type | Should -Be 'IntunePolicyGroups'

        $script:Written.Clear(); $script:Requests.Clear()
        & $Collector -TenantFilter 'contoso.com' -SkipGroupSnapshot
        @($script:Requests | Where-Object { $_ -match '/groups' }).Count | Should -Be 0
        @($script:Written | Where-Object Type -Like '*Groups').Count | Should -Be 0
        $script:Written.Count | Should -BeGreaterThan 0
    }

    It 'writes the snapshot as an authoritative set, and keeps the old one when Graph fails' {
        Set-CIPPDBCacheIntunePolicyGroups -TenantFilter 'contoso.com'
        $script:Written[0].Type | Should -Be 'IntunePolicyGroups'
        $script:Written[0].Count | Should -Be 1
        $script:Written[0].ClearOnEmpty | Should -BeTrue

        $script:Written.Clear()
        $script:GraphFails = $true
        Set-CIPPDBCacheIntunePolicyGroups -TenantFilter 'contoso.com'
        $script:Written.Count | Should -Be 0
    }

    It 'lets the nightly Intune group skip the snapshot after IntunePolicies wrote it' {
        $Types = (Get-CIPPDBCacheSchedule).Intune.Types
        $Types.IndexOf('IntunePolicies') | Should -BeLessThan $Types.IndexOf('IntuneApplications')
        $script:Calls = @{}
        # Defined in this block's scope, so they shadow the real collectors only for this call
        foreach ($Type in $Types) {
            $Collector = if ($Type -in 'IntuneApplications', 'IntuneAppProtectionPolicies', 'IntuneScripts') {
                { param($TenantFilter, $QueueId, [switch]$SkipGroupSnapshot) $script:Calls[$MyInvocation.MyCommand.Name] = $SkipGroupSnapshot.IsPresent }
            } else { { param($TenantFilter, $QueueId) } }
            Set-Item -Path "function:Set-CIPPDBCache$Type" -Value $Collector
        }
        function Get-CIPPIntuneReportExportJob { param($TenantFilter, $ReportName) }

        $Result = Invoke-CIPPDBCacheCollection -CollectionType 'Intune' -TenantFilter 'contoso.com' 6>$null

        $Result.Failed | Should -Be 0
        $script:Calls.Count | Should -Be 3
        @($script:Calls.Values) | Should -Be @($true, $true, $true)
    }

    It 'names an existing collector in every report page sync' {
        $Names = foreach ($Page in (Get-ChildItem $script:PagesRoot -Recurse -Include '*.js', '*.jsx')) {
            foreach ($Match in [regex]::Matches((Get-Content $Page.FullName -Raw), 'cacheName:\s*[''"]([A-Za-z0-9]+)[''"]')) { $Match.Groups[1].Value }
        }
        $Registry = Get-Content (Join-Path $RepoRoot 'Config/CIPPDBCacheTypes.json') -Raw | ConvertFrom-Json
        $Missing = foreach ($Name in ($Names | Sort-Object -Unique)) {
            $Collector = ($Registry | Where-Object type -EQ $Name).collectedBy ?? $Name
            if (-not ($script:Collectors.BaseName -contains "Set-CIPPDBCache$Collector")) { $Name }
        }
        $Names | Should -Not -BeNullOrEmpty
        $Missing | Should -BeNullOrEmpty
    }
}

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') -ErrorAction SilentlyContinue

    function Assert-CIPPMicrosoftHost { param($Uri) }
    function Get-AuthorisedRequest { param($Uri, $TenantID) $true }
    function Get-GraphToken { param($tenantid, $scope, $AsApp, $SkipCache, [switch]$UseCertificate) @{ Authorization = 'Bearer test' } }
    function Get-CippUserAgent { param([switch]$SharePoint) 'test' }
    function Invoke-CIPPRestMethod { param($Uri, $Method, $Headers, $ContentType, $ResponseHeadersVariable) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Add-CIPPDbItem {
        [CmdletBinding()]
        param(
            [string]$TenantFilter,
            [string]$Type,
            [Parameter(ValueFromPipeline)][AllowNull()][AllowEmptyCollection()]$InputObject,
            [switch]$AddCount,
            [switch]$ClearOnEmpty
        )
        begin { $script:Write = @{ Type = $Type; AddCount = $AddCount.IsPresent; ClearOnEmpty = $ClearOnEmpty.IsPresent; Rows = [System.Collections.Generic.List[object]]::new() } }
        process { if ($null -ne $InputObject) { $script:Write.Rows.Add($InputObject) } }
    }

    foreach ($File in 'Get-CIPPDBCacheSchedule.ps1', 'Get-CIPPTenantCapabilities.ps1', 'Test-CIPPCacheCapabilityError.ps1', 'New-GraphGetRequest.ps1') {
        . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $File -File | Select-Object -First 1 -ExpandProperty FullName)
    }
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheDefenderMachines.ps1')

    $script:AvUri = 'https://api.securitycenter.microsoft.com/api/deviceavinfo?$top=10000'
    $script:MachinesUri = 'https://api.securitycenter.microsoft.com/api/machines?$top=10000'
    $script:NextUri = 'https://api.securitycenter.microsoft.com/api/machines?$top=10000&$skip=10000'

    function New-Machine ($Id, $Name = "PC-$Id") {
        [pscustomobject]@{
            id = $Id; computerDnsName = $Name; osPlatform = 'Windows11'; version = '26H2'; osBuild = 26300; osArchitecture = '64-bit'
            healthStatus = 'Active'; onboardingStatus = 'Onboarded'; riskScore = 'None'; exposureLevel = 'None'; deviceValue = 'Normal'
            firstSeen = '2026-11-01T10:00:00Z'; lastSeen = '2026-11-23T10:00:00Z'; lastIpAddress = '10.0.0.5'; lastExternalIpAddress = '203.0.113.9'
            aadDeviceId = $null; machineTags = @('lab'); rbacGroupName = $null; isExcluded = $false; managedBy = 'Unknown'; managedByStatus = 'Unknown'
            osProcessor = 'x64'; ipAddresses = @([pscustomobject]@{ ipAddress = '10.0.0.5'; macAddress = 'AABBCC' })
        }
    }

    function New-Av ($MachineId, $Mode = '0', $Refreshed = '2026-11-23T08:00:00Z', $Seen = '2026-11-23T07:00:00Z', $Signature = 'True', $Version = '1.1') {
        [pscustomobject]@{
            machineId = $MachineId; avMode = $Mode; dataRefreshTimestamp = $Refreshed; lastSeenTime = $Seen
            avSignatureVersion = $Version; avSignatureUpdateTime = '2026-11-23T01:00:00Z'; avIsSignatureUpToDate = $Signature
            avEngineVersion = '1.1.1'; avIsEngineUpToDate = 'Unknown'; avPlatformVersion = '4.18'; avIsPlatformUpToDate = 'False'
            quickScanResult = 'Completed'; quickScanTime = $null; fullScanResult = ''; fullScanTime = $null
        }
    }

    function Set-Page ($Uri, $Value, $Next) {
        $Page = [pscustomobject]@{ '@odata.context' = 'https://api.securitycenter.microsoft.com/api/$metadata'; value = @($Value) }
        if ($Next) { $Page | Add-Member -NotePropertyName '@odata.nextLink' -NotePropertyValue $Next }
        $script:Pages[$Uri] = $Page
    }
}

Describe 'Set-CIPPDBCacheDefenderMachines' {
    BeforeEach {
        $script:Write = $null
        $script:Calls = [System.Collections.Generic.List[string]]::new()
        $script:Pages = @{}
        Set-Page $script:AvUri @()
        Set-Page $script:MachinesUri @((New-Machine 'm1'))
        Mock Invoke-CIPPRestMethod {
            $script:Calls.Add("$Uri")
            $Page = $script:Pages["$Uri"]
            if ($Page -is [string]) { throw $Page }
            $Page
        }
        Mock Get-GraphToken { @{ Authorization = 'Bearer test' } }
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ MDE_SMB = $true } }
        Mock Write-LogMessage {}
        Mock Get-CippException { @{ NormalizedError = $Exception.Exception.Message } }
    }

    It 'reads both feeds with the Defender app token and follows the machine continuation' {
        Set-Page $script:MachinesUri @((New-Machine 'm1'), (New-Machine 'm2')) $script:NextUri
        Set-Page $script:NextUri @((New-Machine 'm3'))
        Set-CIPPDBCacheDefenderMachines -TenantFilter 'contoso.com'
        $script:Calls | Should -Be @($script:AvUri, $script:MachinesUri, $script:NextUri)
        Should -Invoke Get-GraphToken -Times 2 -Exactly -ParameterFilter {
            $tenantid -eq 'contoso.com' -and $AsApp -eq $true -and $scope -eq 'https://api.securitycenter.microsoft.com/.default'
        }
        $script:Write.Type | Should -Be 'DefenderMachines'
        $script:Write.AddCount | Should -BeTrue
        $script:Write.ClearOnEmpty | Should -BeFalse
        $script:Write.Rows.id | Should -Be @('m1', 'm2', 'm3')
    }

    It 'caches the inventory for a Plan 1-only tenant without calling the antivirus API' {
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ MDE_LITE = $true } }
        $script:Pages[$script:AvUri] = 'Forbidden'
        Set-CIPPDBCacheDefenderMachines -TenantFilter 'contoso.com'
        $script:Calls | Should -Be @($script:MachinesUri)
        $script:Write.Rows.id | Should -Be 'm1'
        $script:Write.Rows[0].avMode | Should -BeNullOrEmpty
    }

    It 'joins antivirus health by machine id, keeps unmatched devices and drops the NIC list' {
        Mock Get-CIPPTenantCapabilities { [pscustomobject]@{ MDE_LITE = $true; WINDEFATP = $true } }
        Set-Page $script:MachinesUri @((New-Machine 'm1'), (New-Machine 'm2'))
        Set-Page $script:AvUri @((New-Av 'm1' -Signature 'False'))
        Set-CIPPDBCacheDefenderMachines -TenantFilter 'contoso.com'
        $Joined, $Unmatched = $script:Write.Rows
        $Joined.avMode | Should -Be 'Active'
        $Joined.avIsSignatureUpToDate | Should -Be 'False'
        $Joined.avIsEngineUpToDate | Should -Be 'Unknown'
        $Joined.avIsPlatformUpToDate | Should -Be 'False'
        $Joined.quickScanTime | Should -BeNullOrEmpty
        $Joined.managedBy | Should -Be 'Unknown'
        $Joined.Keys | Should -Not -Contain 'ipAddresses'
        $Joined.Keys | Should -Not -Contain 'osProcessor'
        $Unmatched.computerDnsName | Should -Be 'PC-m2'
        $Unmatched.avMode | Should -BeNullOrEmpty
        $Unmatched.avIsSignatureUpToDate | Should -BeNullOrEmpty
    }

    It 'maps Defender antivirus modes' {
        $Modes = @('0', '1', '2', '3', '4', '5', '')
        Set-Page $script:MachinesUri @(foreach ($Mode in $Modes) { New-Machine "m$Mode" })
        Set-Page $script:AvUri @(foreach ($Mode in $Modes) { New-Av "m$Mode" -Mode $Mode })
        Set-CIPPDBCacheDefenderMachines -TenantFilter 'contoso.com'
        $script:Write.Rows.avMode | Should -Be @('Active', 'Passive', 'Disabled', 'Other', 'EDR Blocked', 'Passive Audit', 'Other')
    }

    It 'keeps the freshest duplicate antivirus record whatever the order, deciding on <Name>' -ForEach @(
        @{ Name = 'refresh time'; Old = @{ Version = '1.0'; Refreshed = '2026-11-23T01:00:00Z' }; New = @{ Version = '2.0'; Refreshed = '2026-11-23T02:00:00Z' } }
        @{ Name = 'missing refresh time'; Old = @{ Version = '1.0'; Refreshed = $null }; New = @{ Version = '2.0'; Refreshed = '2026-11-23T01:00:00Z' } }
    ) {
        $Older = New-Av 'm1' @Old
        $Newer = New-Av 'm1' @New
        foreach ($Order in @($Older, $Newer), @($Newer, $Older)) {
            $script:Write = $null
            Set-Page $script:AvUri $Order
            Set-CIPPDBCacheDefenderMachines -TenantFilter 'contoso.com'
            $script:Write.Rows[0].avSignatureVersion | Should -Be '2.0'
        }
    }

    It 'fails without writing when a device has no id' {
        Set-Page $script:MachinesUri @((New-Machine 'm1'), (New-Machine $null))
        { Set-CIPPDBCacheDefenderMachines -TenantFilter 'contoso.com' } | Should -Throw '*without an id*'
        $script:Write | Should -BeNullOrEmpty
    }

    It 'fails without writing when an antivirus record has no machine id' {
        Set-Page $script:AvUri @((New-Av $null))
        { Set-CIPPDBCacheDefenderMachines -TenantFilter 'contoso.com' } | Should -Throw '*without a machineId*'
        $script:Write | Should -BeNullOrEmpty
    }

    It 'fails without writing when a later machines page fails' {
        Set-Page $script:MachinesUri @((New-Machine 'm1')) $script:NextUri
        $script:Pages[$script:NextUri] = 'Service unavailable'
        { Set-CIPPDBCacheDefenderMachines -TenantFilter 'contoso.com' } | Should -Throw '*Service unavailable*'
        $script:Write | Should -BeNullOrEmpty
    }

    It 'fails without writing when the antivirus read is refused' {
        $script:Pages[$script:AvUri] = 'Forbidden'
        { Set-CIPPDBCacheDefenderMachines -TenantFilter 'contoso.com' } | Should -Throw '*Forbidden*'
        $script:Write | Should -BeNullOrEmpty
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' }
    }

    It 'does not clear the cache when the machines read fails with a not found error' {
        $script:Pages[$script:MachinesUri] = 'No recent machines found'
        { Set-CIPPDBCacheDefenderMachines -TenantFilter 'contoso.com' } | Should -Throw
        $script:Write | Should -BeNullOrEmpty
    }

    It 'skips a tenant that is not provisioned for Defender without an error' {
        $script:Pages[$script:AvUri] = 'No active license found'
        { Set-CIPPDBCacheDefenderMachines -TenantFilter 'contoso.com' } | Should -Not -Throw
        $script:Write | Should -BeNullOrEmpty
        Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $sev -eq 'Error' }
    }


    It 'replaces the cache with an empty snapshot when Defender returns no devices' {
        Set-Page $script:MachinesUri @()
        Set-CIPPDBCacheDefenderMachines -TenantFilter 'contoso.com'
        $script:Write.Rows.Count | Should -Be 0
        $script:Write.AddCount | Should -BeTrue
        $script:Write.ClearOnEmpty | Should -BeTrue
    }
}

Describe 'DefenderMachines registration' {
    It 'registers the collector, cache type, and app permission' {
        (Get-CIPPDBCacheSchedule).Defender.Types | Should -Contain 'DefenderMachines'
        $Backend = (Get-Content (Join-Path $RepoRoot 'Config/CIPPDBCacheTypes.json') -Raw | ConvertFrom-Json).Where({ $_.type -eq 'DefenderMachines' })
        $Frontend = (Get-Content (Join-Path $RepoRoot '../frontend/src/data/CIPPDBCacheTypes.json') -Raw | ConvertFrom-Json).Where({ $_.type -eq 'DefenderMachines' })
        $Backend.Count | Should -Be 1
        ($Frontend | ConvertTo-Json -Compress) | Should -Be ($Backend | ConvertTo-Json -Compress)

        $Manifest = Get-Content (Join-Path $RepoRoot 'Config/SAMManifest.json') -Raw | ConvertFrom-Json
        $Access = $Manifest.requiredResourceAccess.Where({ $_.resourceAppId -eq 'fc780465-2017-40d4-a0c5-307022471b92' }).resourceAccess
        $Access.Where({ $_.id -eq 'ea8291d3-4b9a-44b5-bc3a-6cea3026dc79' }).type | Should -Be 'Role'
    }
}

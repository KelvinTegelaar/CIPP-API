BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

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
        begin { $script:Write = @{ TenantFilter = $TenantFilter; Type = $Type; AddCount = $AddCount.IsPresent; ClearOnEmpty = $ClearOnEmpty.IsPresent; Rows = [System.Collections.Generic.List[object]]::new() } }
        process { if ($null -ne $InputObject) { $script:Write.Rows.Add($InputObject) } }
    }

    foreach ($File in 'Get-CIPPDBCacheSchedule.ps1', 'Test-CIPPCacheCapabilityError.ps1', 'New-GraphGetRequest.ps1', 'Get-CIPPDefenderIndicator.ps1') {
        . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $File -File | Select-Object -First 1 -ExpandProperty FullName)
    }
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheDefenderIndicators.ps1')

    function Get-PageUri ([int]$Top, [int]$Skip) { "https://api.securitycenter.microsoft.com/api/indicators?`$top=$Top&`$skip=$Skip" }
    function New-Indicator ($Id) {
        [pscustomobject]@{
            id = $Id; indicatorValue = "$Id.example"; indicatorType = 'DomainName'; action = 'Block'; title = "Block $Id"; description = 'tech@msp.example via CIPP'
            severity = 'Medium'; generateAlert = $false; expirationTime = $null; creationTimeDateTimeUtc = '2026-11-23T20:00:00Z'; createdByDisplayName = 'CIPP-SAM'
            createdBySource = 'PublicApi'; lastUpdateTime = '2026-11-23T20:00:00Z'; lastUpdatedBy = 'CIPP-SAM'; rbacGroupNames = @(); rbacGroupIds = @(7); application = $null
            source = 'CIPP-SAM'; sourceType = 'AadApp'; category = 1; mitreTechniques = @(); recommendedActions = $null; createdBy = '0b7f1a52-5a0e-4c8e-9f7a-1d2c3b4a5f60'
        }
    }
    function Set-Page ($Uri, $Value) {
        $script:Pages[$Uri] = [pscustomobject]@{ '@odata.context' = 'https://api.securitycenter.microsoft.com/api/$metadata#Indicators'; value = @($Value) }
    }
}

Describe 'Get-CIPPDefenderIndicator' {
    BeforeEach {
        $script:Calls = [System.Collections.Generic.List[string]]::new()
        $script:Pages = @{}
        Mock Invoke-CIPPRestMethod {
            $script:Calls.Add("$Uri")
            $Page = $script:Pages["$Uri"]
            if ($null -eq $Page) { throw "Unexpected request $Uri" }
            if ($Page -is [string]) { throw $Page }
            $Page
        }
        Mock Get-GraphToken { @{ Authorization = 'Bearer test' } }
    }

    It 'reads one page with the Defender app token and stops on a short page' {
        Set-Page (Get-PageUri 10000 0) @((New-Indicator 1), (New-Indicator 2))
        $Indicators = @(Get-CIPPDefenderIndicator -TenantFilter 'contoso.com')
        $script:Calls | Should -Be @((Get-PageUri 10000 0))
        $Indicators.id | Should -Be @('1', '2')
        Should -Invoke Get-GraphToken -Times 1 -Exactly -ParameterFilter {
            $tenantid -ceq 'contoso.com' -and $AsApp -eq $true -and $scope -eq 'https://api.securitycenter.microsoft.com/.default'
        }
    }

    It 'pages with $top and $skip until a short page, without fetching a page twice' {
        Set-Page (Get-PageUri 2 0) @((New-Indicator 1), (New-Indicator 2))
        Set-Page (Get-PageUri 2 2) @((New-Indicator 3), (New-Indicator 4))
        Set-Page (Get-PageUri 2 4) @((New-Indicator 5))
        $Indicators = @(Get-CIPPDefenderIndicator -TenantFilter 'contoso.com' -PageSize 2)
        $script:Calls | Should -Be @((Get-PageUri 2 0), (Get-PageUri 2 2), (Get-PageUri 2 4))
        $Indicators.id | Should -Be @('1', '2', '3', '4', '5')
    }

    It 'stops on an empty page after a full one' {
        Set-Page (Get-PageUri 2 0) @((New-Indicator 1), (New-Indicator 2))
        Set-Page (Get-PageUri 2 2) @()
        @(Get-CIPPDefenderIndicator -TenantFilter 'contoso.com' -PageSize 2).Count | Should -Be 2
        $script:Calls.Count | Should -Be 2
    }

    It 'returns nothing for a tenant without indicators' {
        Set-Page (Get-PageUri 10000 0) @()
        @(Get-CIPPDefenderIndicator -TenantFilter 'contoso.com').Count | Should -Be 0
    }

    It 'throws when a later page fails' {
        Set-Page (Get-PageUri 2 0) @((New-Indicator 1), (New-Indicator 2))
        $script:Pages[(Get-PageUri 2 2)] = 'Service unavailable'
        { @(Get-CIPPDefenderIndicator -TenantFilter 'contoso.com' -PageSize 2) } | Should -Throw '*Service unavailable*'
    }

    It 'throws when an indicator has no id' {
        Set-Page (Get-PageUri 10000 0) @((New-Indicator $null))
        { @(Get-CIPPDefenderIndicator -TenantFilter 'contoso.com') } | Should -Throw '*without an id*'
    }

    It 'keeps the fields CIPP reads and drops the rest' {
        Set-Page (Get-PageUri 10000 0) @((New-Indicator 7))
        $Indicator = @(Get-CIPPDefenderIndicator -TenantFilter 'contoso.com')[0]
        $Indicator.id | Should -BeOfType [string]
        $Indicator.indicatorValue | Should -Be '7.example'
        $Indicator.action | Should -Be 'Block'
        $Indicator.createdByDisplayName | Should -Be 'CIPP-SAM'
        $Indicator.rbacGroupIds | Should -Be @(7)
        $Indicator.Keys | Should -Not -Contain 'createdBy'
        $Indicator.Keys | Should -Not -Contain 'mitreTechniques'
        $Indicator.Keys | Should -Not -Contain 'sourceType'
    }
}

Describe 'Set-CIPPDBCacheDefenderIndicators' {
    BeforeEach {
        $script:Write = $null
        $script:Calls = [System.Collections.Generic.List[string]]::new()
        $script:Pages = @{}
        Mock Invoke-CIPPRestMethod {
            $script:Calls.Add("$Uri")
            $Page = $script:Pages["$Uri"]
            if ($null -eq $Page) { throw "Unexpected request $Uri" }
            if ($Page -is [string]) { throw $Page }
            $Page
        }
        Mock Get-GraphToken { @{ Authorization = 'Bearer test' } }
        Mock Write-LogMessage {}
        Mock Get-CippException { @{ NormalizedError = $Exception.Exception.Message } }
    }

    It 'caches every indicator with a count marker' {
        Set-Page (Get-PageUri 10000 0) @((New-Indicator 1), (New-Indicator 2))
        Set-CIPPDBCacheDefenderIndicators -TenantFilter 'contoso.com'
        $script:Write.TenantFilter | Should -Be 'contoso.com'
        $script:Write.Type | Should -Be 'DefenderIndicators'
        $script:Write.AddCount | Should -BeTrue
        $script:Write.ClearOnEmpty | Should -BeFalse
        $script:Write.Rows.id | Should -Be @('1', '2')
        Should -Invoke Get-GraphToken -Times 1 -Exactly -ParameterFilter { $tenantid -ceq 'contoso.com' -and $AsApp -eq $true }
    }

    It 'stores an indicator once when Defender repeats it across pages' {
        Mock Get-CIPPDefenderIndicator { @{ id = '1'; action = 'Block' }; @{ id = '1'; action = 'Block' }; @{ id = '2'; action = 'Allowed' } }
        Set-CIPPDBCacheDefenderIndicators -TenantFilter 'contoso.com'
        $script:Write.Rows.id | Should -Be @('1', '2')
    }

    It 'replaces the cache with an empty snapshot when the tenant has no indicators' {
        Set-Page (Get-PageUri 10000 0) @()
        Set-CIPPDBCacheDefenderIndicators -TenantFilter 'contoso.com'
        $script:Write.Rows.Count | Should -Be 0
        $script:Write.AddCount | Should -BeTrue
        $script:Write.ClearOnEmpty | Should -BeTrue
    }

    It 'fails without writing when a later page fails' {
        Mock Get-CIPPDefenderIndicator { @{ id = '1' }; throw 'Service unavailable' }
        { Set-CIPPDBCacheDefenderIndicators -TenantFilter 'contoso.com' } | Should -Throw '*Service unavailable*'
        $script:Write | Should -BeNullOrEmpty
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' }
    }

    It 'skips a tenant that is not provisioned for Defender without an error' {
        $script:Pages[(Get-PageUri 10000 0)] = 'No active license found'
        { Set-CIPPDBCacheDefenderIndicators -TenantFilter 'contoso.com' } | Should -Not -Throw
        $script:Write | Should -BeNullOrEmpty
        Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $sev -eq 'Error' }
    }
}

Describe 'DefenderIndicators registration' {
    It 'registers the collector under the Defender for Endpoint licence, the cache type and the app permission' {
        $Schedule = Get-CIPPDBCacheSchedule
        $Schedule.Defender.Types | Should -Contain 'DefenderIndicators'
        $Schedule.Defender.License | Should -Be 'DefenderForEndpoint'
        $Backend = (Get-Content (Join-Path $RepoRoot 'Config/CIPPDBCacheTypes.json') -Raw | ConvertFrom-Json).Where({ $_.type -eq 'DefenderIndicators' })
        $Frontend = (Get-Content (Join-Path $RepoRoot '../frontend/src/data/CIPPDBCacheTypes.json') -Raw | ConvertFrom-Json).Where({ $_.type -eq 'DefenderIndicators' })
        $Backend.Count | Should -Be 1
        ($Frontend | ConvertTo-Json -Compress) | Should -Be ($Backend | ConvertTo-Json -Compress)
        Get-Content (Join-Path $RepoRoot '../frontend/src/utils/cippdb-cache-categories.js') -Raw | Should -Match 'Defender:\s*\[[^\]]*"DefenderIndicators"'

        $Manifest = Get-Content (Join-Path $RepoRoot 'Config/SAMManifest.json') -Raw | ConvertFrom-Json
        $Access = $Manifest.requiredResourceAccess.Where({ $_.resourceAppId -eq 'fc780465-2017-40d4-a0c5-307022471b92' }).resourceAccess
        $Access.Where({ $_.id -eq 'fc511a58-3adf-4d71-af24-00f13e35e479' }).type | Should -Be 'Role'
    }
}

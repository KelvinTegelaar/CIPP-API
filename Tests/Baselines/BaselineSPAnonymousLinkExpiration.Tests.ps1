# SPAnonymousLinkExpiration is a single-file (declarative) definition: no prepare hook, no
# named executor. What can go wrong is therefore in the definition itself and in how the
# engine renders it - a misspelled SPOTenant property grades against nothing, a blank
# optional picker leaves its raw token in the write, a number saved as "30" never equals
# a cached 30. These tests run the REAL definition through the REAL engine against a
# mocked SPOTenant cache row and pin the grading verdicts and the write shape handed to
# the SPOTenant executor.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Set-CippBaselineRunContext { param($RunId) }
    function Update-CippQueueEntry { param($RowKey, $Status, $Name) }
    function Get-CippTable { param($tablename) @{} }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Remove-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Add-CIPPBaselineHistoryEvent { param($TenantFilter, $Standard, $Mode, $TriggeredBy, $Outcome, $Detail, $RunId, $Remediated) }
    function Set-CIPPBaselineResult { param($Result, $Prior, $RunId) }
    function Send-CIPPBaselineAlert { param($Result) }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Get-CIPPTenantCapabilities { param($TenantFilter) }
    function Get-CIPPBaselineDefinition { param($Name) }
    function Wait-CIPPBaselineCacheReady { param($TenantFilter, $Definition, $RunId) $false }
    # The engine resolves both by naming convention with Get-Command; stubs keep the
    # resolution honest without touching SharePoint.
    function Set-CIPPDBCacheSPOTenant { param($TenantFilter) }
    function Invoke-CIPPBaselineSPOTenant { param($Remediate, $TenantFilter, $Current) }
    function Get-CIPPSPOTenant { param($TenantFilter) }
    function Set-CIPPSPOTenant { [CmdletBinding()] param([Parameter(ValueFromPipeline = $true)]$InputObject, $Properties, $MethodName, $MethodParameters, [switch]$UseCertificate) process { } }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Invoke-CIPPBaselineStandard.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:DefinitionPath = Join-Path $script:RepoRoot 'Config/BaselineStandards/SharePoint Standards/SPAnonymousLinkExpiration.json'
    $script:Definition = Get-Content $script:DefinitionPath -Raw | ConvertFrom-Json

    # The frontend posts number inputs as strings and picker selections as {label, value}
    # wrappers - the fixtures mirror what a saved baseline really holds.
    function New-EngineItem {
        param($Variables)
        @{
            TenantFilter = $script:Tenant; Standard = 'SPAnonymousLinkExpiration'; BaseName = 'SPAnonymousLinkExpiration'
            Variables = $Variables; Tiers = @(); AlertEnabled = $false; RemediateEnabled = $true
        }
    }
    $script:ViewOnly = [PSCustomObject]@{ label = 'View only'; value = 1 }
    # Get-CIPPSPOTenant output round-trips through the CIPPDb as JSON, so cached numbers are Int64.
    function New-CachedTenant {
        param([int]$ExpireDays, [int]$FileLink = 2, [int]$FolderLink = 2)
        [PSCustomObject]@{
            SharingCapability                 = 2
            RequireAnonymousLinksExpireInDays = $ExpireDays
            FileAnonymousLinkType             = $FileLink
            FolderAnonymousLinkType           = $FolderLink
            DefaultSharingLinkType            = 1
        } | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    }
}

Describe 'SPAnonymousLinkExpiration definition' {
    BeforeEach {
        Mock Get-CIPPBaselineDefinition { $script:Definition }
        Mock Get-CIPPAzDataTableEntity { @() }
        Mock Set-CIPPBaselineResult { }
        Mock Add-CIPPBaselineHistoryEvent { }
        Mock Send-CIPPBaselineAlert { }
        Mock Write-LogMessage { }
        Mock Invoke-CIPPBaselineSPOTenant { }
        # compare/run modes pass the licence gate; oneoff skips it. Flat list = any-of.
        Mock Get-CIPPTenantCapabilities { [PSCustomObject]@{ SHAREPOINTSTANDARD = $true } }
    }

    Context 'grading' {
        It 'is compliant when the tenant expiry matches and the picked permission holds on files AND folders' {
            Mock New-CIPPDbRequest { New-CachedTenant -ExpireDays 30 -FileLink 1 -FolderLink 1 }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ days = '30'; linkPermission = $script:ViewOnly })) -Mode 'compare'
            $Result.Compliant | Should -BeTrue
            # The number variable is saved as the STRING "30"; the engine must coerce it on the
            # declared type or the compare is a permanent string-vs-number drift.
            $Result.ExpectedValue.RequireAnonymousLinksExpireInDays | Should -BeExactly 30
            $Result.ExpectedValue.RequireAnonymousLinksExpireInDays | Should -Not -BeOfType [string]
        }

        It 'grades the SharePoint default (-1 = no expiration required) as drift on the expiry property' {
            # Observed live: a tenant with no expiration policy caches RequireAnonymousLinksExpireInDays as -1,
            # not the 0 the Set-SPOTenant docs describe for removing the requirement.
            Mock New-CIPPDbRequest { New-CachedTenant -ExpireDays -1 -FileLink 1 -FolderLink 1 }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ days = '30'; linkPermission = $script:ViewOnly })) -Mode 'compare'
            $Result.Compliant | Should -BeFalse
            @($Result.Diff).Property | Should -Contain 'RequireAnonymousLinksExpireInDays'
        }

        It 'grades a longer-than-baseline expiry as drift - the standard pins the value, not a ceiling' {
            Mock New-CIPPDbRequest { New-CachedTenant -ExpireDays 90 -FileLink 1 -FolderLink 1 }
            (Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ days = '30'; linkPermission = $script:ViewOnly })) -Mode 'compare').Compliant | Should -BeFalse
        }

        It 'grades a folder permission looser than the pick as drift even when files comply' {
            Mock New-CIPPDbRequest { New-CachedTenant -ExpireDays 30 -FileLink 1 -FolderLink 2 }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ days = '30'; linkPermission = $script:ViewOnly })) -Mode 'compare'
            $Result.Compliant | Should -BeFalse
            @($Result.Diff).Property | Should -Contain 'FolderAnonymousLinkType'
            @($Result.Diff).Property | Should -Not -Contain 'FileAnonymousLinkType'
        }

        It 'with the permission left blank, grades expiry ONLY and expresses no opinion on link permissions' {
            # Anyone links at Edit on both surfaces must not drift a baseline that never asked.
            Mock New-CIPPDbRequest { New-CachedTenant -ExpireDays 30 -FileLink 2 -FolderLink 2 }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ days = '30' })) -Mode 'compare'
            $Result.Compliant | Should -BeTrue
            $Result.ExpectedValue.PSObject.Properties.Name | Should -Not -Contain 'FileAnonymousLinkType'
            $Result.ExpectedValue.PSObject.Properties.Name | Should -Not -Contain 'FolderAnonymousLinkType'
        }

        It 'applies the declared 30-day default when the days variable was never filled in' {
            Mock New-CIPPDbRequest { New-CachedTenant -ExpireDays 30 }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{})) -Mode 'compare'
            $Result.ExpectedValue.RequireAnonymousLinksExpireInDays | Should -BeExactly 30
            $Result.Compliant | Should -BeTrue
        }

        It 'reports No Data rather than drift when the SPOTenant cache is empty' {
            Mock New-CIPPDbRequest { @() }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ days = '30' })) -Mode 'compare'
            $Result.Compliant | Should -BeFalse
            $Result.Outcome | Should -Not -Be 'Drift'
        }
    }

    Context 'remediation' {
        It 'hands the SPOTenant executor all three properties, numerically typed, when a permission is picked' {
            Mock New-CIPPDbRequest { New-CachedTenant -ExpireDays -1 }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ days = '30'; linkPermission = $script:ViewOnly })) -Mode 'oneoff'
            $Result.Remediated | Should -BeTrue
            Should -Invoke Invoke-CIPPBaselineSPOTenant -Times 1 -Exactly -ParameterFilter {
                $TenantFilter -eq $script:Tenant -and
                $Remediate.properties.RequireAnonymousLinksExpireInDays -eq 30 -and
                $Remediate.properties.RequireAnonymousLinksExpireInDays -isnot [string] -and
                $Remediate.properties.FileAnonymousLinkType -eq 1 -and
                $Remediate.properties.FolderAnonymousLinkType -eq 1 -and
                -not $Remediate.PSObject.Properties['methods']
            }
        }

        It 'prunes BOTH permission properties from the write when the picker is blank - no raw token reaches SharePoint' {
            Mock New-CIPPDbRequest { New-CachedTenant -ExpireDays -1 }
            $null = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ days = '45' })) -Mode 'oneoff'
            Should -Invoke Invoke-CIPPBaselineSPOTenant -Times 1 -Exactly -ParameterFilter {
                $Remediate.properties.RequireAnonymousLinksExpireInDays -eq 45 -and
                -not $Remediate.properties.PSObject.Properties['FileAnonymousLinkType'] -and
                -not $Remediate.properties.PSObject.Properties['FolderAnonymousLinkType'] -and
                (ConvertTo-Json -Compress -InputObject $Remediate) -notmatch '%'
            }
        }

        It 'does not write when the tenant already complies' {
            Mock New-CIPPDbRequest { New-CachedTenant -ExpireDays 30 -FileLink 1 -FolderLink 1 }
            $null = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ days = '30'; linkPermission = $script:ViewOnly })) -Mode 'run'
            Should -Invoke Invoke-CIPPBaselineSPOTenant -Times 0 -Exactly
        }
    }
}

Describe 'SPOTenant executor wire shape' {
    BeforeAll {
        . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Baselines/Invoke-CIPPBaselineSPOTenant.ps1')
    }

    It 'sends the rendered properties to Set-CIPPSPOTenant as Int32 - the CSOM whitelist drops Int64 silently' {
        Mock Get-CIPPSPOTenant { [PSCustomObject]@{ _ObjectIdentity_ = 'id'; TenantFilter = $script:Tenant } }
        Mock Set-CIPPSPOTenant { }
        # Exactly what the engine renders: JSON round-trip makes every number Int64.
        $Spec = '{"executor":"SPOTenant","properties":{"RequireAnonymousLinksExpireInDays":30,"FileAnonymousLinkType":1,"FolderAnonymousLinkType":1}}' | ConvertFrom-Json
        Invoke-CIPPBaselineSPOTenant -Remediate $Spec -TenantFilter $script:Tenant -Current $null
        Should -Invoke Set-CIPPSPOTenant -Times 1 -Exactly -ParameterFilter {
            $Properties.Count -eq 3 -and
            $Properties['RequireAnonymousLinksExpireInDays'] -is [int] -and $Properties['RequireAnonymousLinksExpireInDays'] -eq 30 -and
            $Properties['FileAnonymousLinkType'] -is [int] -and $Properties['FileAnonymousLinkType'] -eq 1 -and
            $Properties['FolderAnonymousLinkType'] -is [int] -and $Properties['FolderAnonymousLinkType'] -eq 1
        }
    }
}

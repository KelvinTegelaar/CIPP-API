# MigrateOneDriveShortcuts grades declaratively off the OneDriveRootShortcuts summary row. These
# tests pin the collector's batched scan, the executor's folder resolution and its hand-off to
# GraphBulkSweep, and the REAL engine's verdicts on the definition.

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
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount) }
    function Set-CIPPDBCacheUsers { param($TenantFilter) }
    function New-GraphBulkRequest { param($tenantid, $Requests, $asapp, $scope, $Version) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Get-CIPPTenantCapabilities { param($TenantFilter) }
    function Get-CIPPBaselineDefinition { param($Name) }
    function Wait-CIPPBaselineCacheReady { param($TenantFilter, $Definition, $RunId) $false }
    function Get-CippException { param($Exception) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Get-CIPPBaselineCommand.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Invoke-CIPPBaselineStandard.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Executors/Invoke-CIPPBaselineGraphBulkSweep.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Executors/Invoke-CIPPBaselineMigrateOneDriveShortcuts.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheOneDriveRootShortcuts.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:Definition = Get-Content (Join-Path $script:RepoRoot 'Config/BaselineStandards/SharePoint Standards/MigrateOneDriveShortcuts.json') -Raw | ConvertFrom-Json

    $script:Users = @(
        [PSCustomObject]@{ id = 'u-bob'; userPrincipalName = 'bob@contoso.com'; accountEnabled = $true; userType = 'Member' }
        [PSCustomObject]@{ id = 'u-alice'; userPrincipalName = 'alice@contoso.com'; accountEnabled = $true; userType = 'Member' }
        [PSCustomObject]@{ id = 'u-carol'; userPrincipalName = 'carol@contoso.com'; accountEnabled = $true; userType = 'Member' }
        [PSCustomObject]@{ id = 'u-off'; userPrincipalName = 'disabled@contoso.com'; accountEnabled = $false; userType = 'Member' }
        [PSCustomObject]@{ id = 'u-guest'; userPrincipalName = 'guest#EXT#@contoso.com'; accountEnabled = $true; userType = 'Guest' }
        [PSCustomObject]@{ id = 'u-noupn'; userPrincipalName = ''; accountEnabled = $true; userType = 'Member' }
    )
    function New-Listing {
        param($Id, $Status = 200, $Items = @())
        [PSCustomObject]@{ id = $Id; status = $Status; body = [PSCustomObject]@{ value = @($Items); error = [PSCustomObject]@{ message = 'boom' } } }
    }
    $script:Shortcut = [PSCustomObject]@{ id = 'i-docs'; name = 'Docs'; remoteItem = [PSCustomObject]@{ id = 'r1' }; parentReference = [PSCustomObject]@{ path = '/drive/root:' } }
    $script:Filed = [PSCustomObject]@{ id = 'i-filed'; name = 'Filed'; remoteItem = [PSCustomObject]@{ id = 'r2' }; parentReference = [PSCustomObject]@{ path = '/drive/root:/Shortcuts' } }
    $script:PlainFile = [PSCustomObject]@{ id = 'i-file'; name = 'notes.txt'; parentReference = [PSCustomObject]@{ path = '/drive/root:' } }

    # The engine reads the summary row as the CIPPDb round-trips it.
    function New-Summary {
        param([string[]]$Offenders = @(), $Targets = @())
        [PSCustomObject]@{ id = 'summary'; offenders = @($Offenders); targets = @($Targets) } | ConvertTo-Json -Depth 5 | ConvertFrom-Json
    }
    function New-EngineItem {
        @{ TenantFilter = $script:Tenant; Standard = 'MigrateOneDriveShortcuts'; BaseName = 'MigrateOneDriveShortcuts'; Variables = [PSCustomObject]@{}; Tiers = @(); AlertEnabled = $false; RemediateEnabled = $true }
    }
}

Describe 'MigrateOneDriveShortcuts definition' {
    It 'reads its own cache declaratively and keeps it fresh through requiredCaches (on-demand, so nothing else refreshes it)' {
        $script:Definition.PSObject.Properties['prepare'] | Should -BeNullOrEmpty
        $script:Definition.read.cacheType | Should -Be 'OneDriveRootShortcuts'
        @($script:Definition.read.requiredCaches) | Should -Contain 'OneDriveRootShortcuts'
        $Registered = Get-Content (Join-Path $script:RepoRoot 'Config/CIPPDBCacheTypes.json') -Raw | ConvertFrom-Json
        @($Registered.type) | Should -Contain 'OneDriveRootShortcuts'
    }
}

Describe 'Set-CIPPDBCacheOneDriveRootShortcuts' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Add-CIPPDbItem {}
        Mock Set-CIPPDBCacheUsers {}
        Mock New-CIPPDbRequest { $script:Users }
        Mock New-GraphBulkRequest {
            @(
                New-Listing 'u-bob' 200 @($script:Shortcut, $script:PlainFile)
                New-Listing 'u-alice' 200 @($script:Shortcut, $script:Filed)
                New-Listing 'u-carol' 200 @($script:Filed, $script:PlainFile)
            )
        }
    }

    It 'lists only enabled members with a UPN, in one batch call, with the AddToOneDrive Prefer header' {
        Set-CIPPDBCacheOneDriveRootShortcuts -TenantFilter $script:Tenant
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
            @($Requests).Count -eq 3 -and
            (@($Requests.id) -join ',') -eq 'u-bob,u-alice,u-carol' -and
            @($Requests).Where({ $_.headers.Prefer -ne 'Include-Feature=AddToOneDrive' -or $_.url -notlike 'users/*/drive/root/children*' }).Count -eq 0 -and
            $asapp -eq $true
        }
    }

    It 'writes one summary row: sorted offenders, and only unfiled remote shortcuts as targets' {
        Set-CIPPDBCacheOneDriveRootShortcuts -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter {
            $Row = @($Data)[0]
            $Type -eq 'OneDriveRootShortcuts' -and $AddCount -and @($Data).Count -eq 1 -and $Row.id -eq 'summary' -and
            (@($Row.offenders) -join ',') -eq 'alice@contoso.com,bob@contoso.com' -and
            @($Row.targets).Count -eq 2 -and
            @($Row.targets).Where({ $_.itemId -ne 'i-docs' }).Count -eq 0 -and
            (@($Row.targets.userId) -join ',') -eq 'u-bob,u-alice'
        }
    }

    It 'writes an empty summary when nobody has root shortcuts' {
        Mock New-GraphBulkRequest { @(New-Listing 'u-bob' 200 @($script:Filed)) }
        Set-CIPPDBCacheOneDriveRootShortcuts -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { @(@($Data)[0].offenders).Count -eq 0 -and @(@($Data)[0].targets).Count -eq 0 }
    }

    It 'skips a user without a OneDrive quietly and warns on other listing failures' {
        Mock New-GraphBulkRequest { @((New-Listing 'u-bob' 404), (New-Listing 'u-alice' 500), (New-Listing 'u-carol' 200 @($script:Shortcut))) }
        Set-CIPPDBCacheOneDriveRootShortcuts -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { (@(@($Data)[0].offenders) -join ',') -eq 'carol@contoso.com' }
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Warning' -and $message -like '*alice@contoso.com*' -and $message -notlike '*bob@*' }
    }

    It 'writes nothing when every listing fails, so the previous verdict stands (<Case>)' -ForEach @(
        @{ Case = 'all forbidden'; Statuses = @(403, 403, 403) }
        @{ Case = 'one without a OneDrive, the rest forbidden'; Statuses = @(404, 403, 403) }
    ) {
        $script:Statuses = $Statuses
        Mock New-GraphBulkRequest { @((New-Listing 'u-bob' $script:Statuses[0]), (New-Listing 'u-alice' $script:Statuses[1]), (New-Listing 'u-carol' $script:Statuses[2])) }
        Set-CIPPDBCacheOneDriveRootShortcuts -TenantFilter $script:Tenant
        Should -Invoke Add-CIPPDbItem -Times 0 -Exactly
    }

    It 'collects the Users cache once when it is empty, and writes nothing if it stays empty' {
        Mock New-CIPPDbRequest { @() }
        Set-CIPPDBCacheOneDriveRootShortcuts -TenantFilter $script:Tenant
        Should -Invoke Set-CIPPDBCacheUsers -Times 1 -Exactly
        Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
        Should -Invoke Add-CIPPDbItem -Times 0 -Exactly
    }
}

Describe 'Invoke-CIPPBaselineMigrateOneDriveShortcuts' {
    BeforeEach {
        Mock Write-LogMessage {}
        Mock Invoke-CIPPBaselineGraphBulkSweep {}
        Mock New-GraphBulkRequest {
            @(
                [PSCustomObject]@{ id = 'u-bob'; status = 200; body = [PSCustomObject]@{ id = 'f-bob' } }
                [PSCustomObject]@{ id = 'u-alice'; status = 404; body = [PSCustomObject]@{ error = [PSCustomObject]@{ message = 'nope' } } }
            )
        }
        $script:Spec = $script:Definition.remediate
        $script:Current = [PSCustomObject]@{
            offenders = @('alice@contoso.com', 'bob@contoso.com')
            targets   = @(
                [PSCustomObject]@{ userId = 'u-bob'; itemId = 'i1' }
                [PSCustomObject]@{ userId = 'u-bob'; itemId = 'i2' }
                [PSCustomObject]@{ userId = 'u-alice'; itemId = 'i3' }
            )
        }
    }

    It 'resolves each user''s Shortcuts folder once, in one batch call' {
        Invoke-CIPPBaselineMigrateOneDriveShortcuts -Remediate $script:Spec -TenantFilter $script:Tenant -Current $script:Current
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
            (@($Requests.id) -join ',') -eq 'u-bob,u-alice' -and @($Requests).Where({ $_.url -notlike 'users/*/drive/special/shortcuts*' }).Count -eq 0
        }
    }

    It 'hands GraphBulkSweep the definition spec with only resolvable targets, carrying folderId' {
        Invoke-CIPPBaselineMigrateOneDriveShortcuts -Remediate $script:Spec -TenantFilter $script:Tenant -Current $script:Current
        Should -Invoke Invoke-CIPPBaselineGraphBulkSweep -Times 1 -Exactly -ParameterFilter {
            $Remediate.writes[0].uri -eq 'users/%userId%/drive/items/%itemId%' -and
            (@($Current.targets.itemId) -join ',') -eq 'i1,i2' -and
            @($Current.targets).Where({ $_.folderId -ne 'f-bob' }).Count -eq 0
        }
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $Sev -eq 'Warning' -and $message -like '*u-alice*' }
    }

    It 'throws when no folder resolves, rather than claiming a remediation' {
        Mock New-GraphBulkRequest { @([PSCustomObject]@{ id = 'u-bob'; status = 403; body = [PSCustomObject]@{} }, [PSCustomObject]@{ id = 'u-alice'; status = 403; body = [PSCustomObject]@{} }) }
        { Invoke-CIPPBaselineMigrateOneDriveShortcuts -Remediate $script:Spec -TenantFilter $script:Tenant -Current $script:Current } | Should -Throw '*no Shortcuts folder*'
        Should -Invoke Invoke-CIPPBaselineGraphBulkSweep -Times 0 -Exactly
    }

    It 'throws without a scan (the engine writes on a null Current)' {
        { Invoke-CIPPBaselineMigrateOneDriveShortcuts -Remediate $script:Spec -TenantFilter $script:Tenant -Current $null } | Should -Throw '*no cached*'
        Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
    }

    It 'is a no-op on a scan with nothing to move (a manual run forces the write on a compliant tenant)' {
        { Invoke-CIPPBaselineMigrateOneDriveShortcuts -Remediate $script:Spec -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ offenders = @(); targets = @() }) } | Should -Not -Throw
        Should -Invoke New-GraphBulkRequest -Times 0 -Exactly
        Should -Invoke Invoke-CIPPBaselineGraphBulkSweep -Times 0 -Exactly
    }
}

Describe 'MigrateOneDriveShortcuts write spec through GraphBulkSweep' {
    It 'expands to the classic move: PATCH users/{id}/drive/items/{item} with parentReference.id = Shortcuts folder, app-only' {
        Mock Write-LogMessage {}
        Mock New-GraphBulkRequest { @([PSCustomObject]@{ id = '0'; status = 200 }) }
        Invoke-CIPPBaselineGraphBulkSweep -Remediate $script:Definition.remediate -TenantFilter $script:Tenant -Current ([PSCustomObject]@{ targets = @([PSCustomObject]@{ userId = 'u-bob'; itemId = 'i1'; folderId = 'f-bob' }) })
        Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
            $Request = @($Requests)[0]
            $Request.method -eq 'PATCH' -and $Request.url -eq '/users/u-bob/drive/items/i1' -and
            $Request.body.parentReference.id -eq 'f-bob' -and $asapp -eq $true
        }
    }
}

Describe 'MigrateOneDriveShortcuts through the engine' {
    BeforeEach {
        Mock Get-CIPPBaselineDefinition { $script:Definition }
        Mock Get-CIPPAzDataTableEntity { @() }
        Mock Set-CIPPBaselineResult {}
        Mock Add-CIPPBaselineHistoryEvent {}
        Mock Send-CIPPBaselineAlert {}
        Mock Write-LogMessage {}
        Mock Set-CIPPDBCacheOneDriveRootShortcuts {}
        Mock Get-CIPPTenantCapabilities { [PSCustomObject]@{ SHAREPOINTSTANDARD = $true } }
        Mock Invoke-CIPPBaselineMigrateOneDriveShortcuts {}
    }

    It 'is compliant on an empty summary and writes nothing in run mode' {
        Mock New-CIPPDbRequest { New-Summary }
        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run'
        $Result.Compliant | Should -BeTrue
        $Result.Remediated | Should -BeFalse
        Should -Invoke Invoke-CIPPBaselineMigrateOneDriveShortcuts -Times 0 -Exactly
    }

    It 'grades offenders as drift and remediates with the cached targets and the writes spec' {
        Mock New-CIPPDbRequest { New-Summary -Offenders 'bob@contoso.com' -Targets @([PSCustomObject]@{ userId = 'u-bob'; userPrincipalName = 'bob@contoso.com'; itemId = 'i1'; name = 'Docs' }) }
        $Compare = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'compare'
        $Compare.Compliant | Should -BeFalse
        $Compare.Outcome | Should -Be 'Drift'
        $Run = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run'
        $Run.Remediated | Should -BeTrue
        Should -Invoke Invoke-CIPPBaselineMigrateOneDriveShortcuts -Times 1 -Exactly -ParameterFilter {
            $Current.targets[0].itemId -eq 'i1' -and $Remediate.writes[0].body.parentReference.id -eq '%folderId%'
        }
    }

    It 'records an Error, not a remediation, when there is no scan to act on' {
        Mock New-CIPPDbRequest { @() }
        Mock Invoke-CIPPBaselineMigrateOneDriveShortcuts { throw 'MigrateOneDriveShortcuts: no cached OneDrive shortcut scan to remediate from.' }
        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run'
        $Result.Remediated | Should -BeFalse
        $Result.Outcome | Should -Be 'Error'
        Should -Invoke Set-CIPPDBCacheOneDriveRootShortcuts -Times 1 -Exactly
    }
}

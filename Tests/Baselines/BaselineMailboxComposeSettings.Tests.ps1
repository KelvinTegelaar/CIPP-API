# MailboxComposeSettings has no prepare hook: read.rows grades every MailboxMessageConfiguration
# row in the engine. These tests run the REAL definition through the REAL engine.

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
    function Set-CIPPBaselineResult { param($Result, $Prior, $RunId, $Detail) }
    function Send-CIPPBaselineAlert { param($Result) }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Get-CIPPTenantCapabilities { param($TenantFilter) }
    function Get-CIPPBaselineDefinition { param($Name) }
    function Wait-CIPPBaselineCacheReady { param($TenantFilter, $Definition, $RunId) $false }
    function Set-CIPPDBCacheMailboxMessageConfiguration { param($TenantFilter) }
    function Invoke-CIPPBaselineExoBulkSweep { param($Remediate, $TenantFilter, $Current) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Get-CIPPBaselineCommand.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Expand-CIPPBaselineToken.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Invoke-CIPPBaselineStandard.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    $script:Definition = Get-Content (Join-Path $script:RepoRoot 'Config/BaselineStandards/Exchange Standards/MailboxComposeSettings.json') -Raw | ConvertFrom-Json

    function New-EngineItem {
        param($Variables)
        @{
            TenantFilter = $script:Tenant; Standard = 'MailboxComposeSettings'; BaseName = 'MailboxComposeSettings'
            Variables = $Variables; Tiers = @(); AlertEnabled = $false; RemediateEnabled = $true
        }
    }
    # Shapes as the collector caches them, round-tripped through JSON (verified live: the interval is an integer, booleans are booleans, format strings are plain)
    function New-Row {
        param($Id, $Undo = 0, $From = $false, $Format = 'Html', $ErrorText, [switch]$Legacy)
        $Row = if ($Legacy) {
            [PSCustomObject]@{ id = $Id; DefaultFontName = 'Aptos'; DefaultFontSize = 3; DefaultFontColor = '#000000'; error = $null }
        } else {
            [PSCustomObject]@{
                id = $Id; MailSendUndoInterval = $Undo; AlwaysShowFrom = $From; AlwaysShowBcc = $false; CheckForForgottenAttachments = $true
                IsReplyAllTheDefaultResponse = $true; DefaultFormat = $Format; ReadReceiptResponse = 'DoNotAutomaticallySend'; LinkPreviewEnabled = $true; error = $ErrorText
            }
        }
        $Row | ConvertTo-Json | ConvertFrom-Json
    }
}

Describe 'MailboxComposeSettings' {
    BeforeEach {
        Mock Get-CIPPBaselineDefinition { $script:Definition }
        Mock Get-CIPPAzDataTableEntity { @() }
        Mock Set-CIPPBaselineResult { }
        Mock Add-CIPPBaselineHistoryEvent { }
        Mock Send-CIPPBaselineAlert { }
        Mock Write-LogMessage { }
        Mock Invoke-CIPPBaselineExoBulkSweep { }
        Mock Set-CIPPDBCacheMailboxMessageConfiguration { }
        Mock Get-CIPPTenantCapabilities { [PSCustomObject]@{ EXCHANGE_S_ENTERPRISE = $true } }
    }

    It 'declares no prepare hook and matches every setting it writes' {
        $script:Definition.prepare | Should -BeNullOrEmpty
        $Written = @($script:Definition.remediate.writes[0].params.PSObject.Properties.Name).Where({ $_ -ne 'Identity' })
        @($script:Definition.read.rows.match.PSObject.Properties.Name) | Should -Be $Written
        @($script:Definition.variables.PSObject.Properties.Name) | Should -Be $Written
    }

    It 'offers real booleans on the on/off pickers - a string "true" would be written to Exchange as a string' {
        foreach ($Variable in $script:Definition.variables.PSObject.Properties) {
            if ($Variable.Value.type -ne 'autoComplete') { continue }
            $Values = @($Variable.Value.options).Where({ "$($_.value)" }).value
            if ($Values[0] -is [bool]) { $Values | Should -BeOfType [bool] }
        }
    }

    Context 'grading' {
        It 'is compliant when every mailbox matches, comparing an integer, a boolean and a case-insensitive string' {
            Mock New-CIPPDbRequest { @(New-Row 'a@contoso.com' -Undo 5 -From $true -Format 'Html'; New-Row 'b@contoso.com' -Undo 5 -From $true -Format 'HTML') }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ MailSendUndoInterval = '5'; AlwaysShowFrom = $true; DefaultFormat = 'html' })) -Mode 'compare'
            $Result.Compliant | Should -BeTrue
        }

        It 'flags only mailboxes that differ on a configured setting and ignores the ones left on Do not change' {
            Mock New-CIPPDbRequest { @(
                    New-Row 'ok@contoso.com' -Undo 10
                    New-Row 'undo@contoso.com' -Undo 0
                    New-Row 'from@contoso.com' -Undo 10 -From $true
                ) }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ MailSendUndoInterval = '10'; AlwaysShowFrom = $false; DefaultFormat = '' })) -Mode 'compare'
            $Result.Compliant | Should -BeFalse
            $Result.CurrentValue.offenders | Should -Be @('from@contoso.com', 'undo@contoso.com')
            $Result.CurrentValue.unreadable | Should -BeNullOrEmpty
        }

        It 'treats a picker wrapper left on Do not change as not configured' {
            Mock New-CIPPDbRequest { @(New-Row 'a@contoso.com' -Format 'PlainText') }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ MailSendUndoInterval = 0; DefaultFormat = [PSCustomObject]@{ label = 'Do not change'; value = '' } })) -Mode 'compare'
            $Result.Compliant | Should -BeTrue
        }

        It 'reports failed reads and rows cached before a setting was collected as unreadable, not compliant' {
            Mock New-CIPPDbRequest { @(New-Row 'ok@contoso.com'; New-Row 'err@contoso.com' -ErrorText 'denied'; New-Row 'old@contoso.com' -Legacy) }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ MailSendUndoInterval = 0 })) -Mode 'compare'
            $Result.Compliant | Should -BeFalse
            $Result.CurrentValue.unreadable | Should -Be @('err@contoso.com', 'old@contoso.com')
            $Result.CurrentValue.offenders | Should -BeNullOrEmpty
        }

        It 'collects again when no row can be read, and grades the fresh cache' {
            $script:Reads = 0
            Mock New-CIPPDbRequest { $script:Reads++; if ($script:Reads -eq 1) { @(New-Row 'a@contoso.com' -Legacy) } else { @(New-Row 'a@contoso.com' -Undo 5) } }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ MailSendUndoInterval = 5 })) -Mode 'compare'
            Should -Invoke Set-CIPPDBCacheMailboxMessageConfiguration -Times 1 -Exactly
            $Result.Compliant | Should -BeTrue
        }

        It 'reports an error naming the cache when no row can be read even after collecting' {
            Mock New-CIPPDbRequest { @(New-Row 'a@contoso.com' -ErrorText 'denied') }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ MailSendUndoInterval = 5 })) -Mode 'run'
            $Result.Outcome | Should -Be 'Error'
            Should -Invoke Write-LogMessage -ParameterFilter { $message -match 'MailboxMessageConfiguration cache could be read' }
            Should -Invoke Invoke-CIPPBaselineExoBulkSweep -Times 0 -Exactly
        }

        It 'reports an error without reading or collecting when no setting is configured' {
            Mock New-CIPPDbRequest { @(New-Row 'a@contoso.com') }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ AlwaysShowFrom = '' })) -Mode 'run'
            $Result.Outcome | Should -Be 'Error'
            Should -Invoke New-CIPPDbRequest -Times 0 -Exactly
            Should -Invoke Set-CIPPDBCacheMailboxMessageConfiguration -Times 0 -Exactly
        }

        It 'returns No Data, not compliant, on an empty cache' {
            Mock New-CIPPDbRequest { @() }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ MailSendUndoInterval = 5 })) -Mode 'compare'
            $Result.Compliant | Should -BeFalse
            $Result.Outcome | Should -Not -Be 'Drift'
            Should -Invoke Set-CIPPDBCacheMailboxMessageConfiguration -Times 1 -Exactly
        }
    }

    Context 'remediation' {
        It 'sweeps only the offenders with only the configured settings, keeping integer and boolean types' {
            Mock New-CIPPDbRequest { @(New-Row 'ok@contoso.com' -Undo 10 -From $true; New-Row 'bad@contoso.com') }
            $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ MailSendUndoInterval = '10'; AlwaysShowFrom = $true; ReadReceiptResponse = '' })) -Mode 'run'
            $Result.Remediated | Should -BeTrue
            Should -Invoke Invoke-CIPPBaselineExoBulkSweep -Times 1 -Exactly -ParameterFilter {
                $Params = $Remediate.writes[0].params
                @($Current.targets).id -join ',' -eq 'bad@contoso.com' -and
                $Remediate.writes[0].cmdlet -eq 'Set-MailboxMessageConfiguration' -and
                (@($Params.PSObject.Properties.Name) -join ',') -eq 'Identity,MailSendUndoInterval,AlwaysShowFrom' -and
                $Params.Identity -eq '%id%' -and
                $Params.MailSendUndoInterval -is [long] -and $Params.MailSendUndoInterval -eq 10 -and
                $Params.AlwaysShowFrom -is [bool] -and $Params.AlwaysShowFrom -eq $true
            }
        }

        It 'does not write when every mailbox already complies' {
            Mock New-CIPPDbRequest { @(New-Row 'ok@contoso.com' -Undo 10) }
            $null = Invoke-CIPPBaselineStandard -Item (New-EngineItem ([PSCustomObject]@{ MailSendUndoInterval = 10 })) -Mode 'run'
            Should -Invoke Invoke-CIPPBaselineExoBulkSweep -Times 0 -Exactly
        }
    }
}

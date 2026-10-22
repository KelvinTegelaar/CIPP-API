# Pester tests for how Get-CIPPBaselineAlignment reads BaselineHistory: the tenant payload never
# does, and -History pushes its filters into the table query and returns newest-first.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $BaselinesPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Baselines'
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $First, $Property) }
    function ConvertTo-CIPPODataFilterValue { param($Value) "$Value" -replace "'", "''" }
    function Get-CIPPBaselineDefinition { }
    function Get-CIPPBaseline { param($ID) }
    function Get-TenantGroups { }
    . (Join-Path $BaselinesPath 'Get-CIPPBaselineAlignment.ps1')
    . (Join-Path $BaselinesPath 'Convert-CIPPBaselineResolvedEntity.ps1')

    $Event = { param($Pk, $Ticks, $RunId) [pscustomobject]@{ PartitionKey = $Pk; RowKey = ('{0:D19}-{1}' -f $Ticks, $RunId); Timestamp = 100; RunId = $RunId; Mode = 'compare'; Outcome = 'Drift' } }
    # Lower inverted ticks = newer. abc holds the newest and the oldest event, def the middle one.
    $script:HistoryRows = @{
        't1.com_ConditionalAccessTemplate~abc' = @((& $Event 't1.com_ConditionalAccessTemplate~abc' 100 'newest'), (& $Event 't1.com_ConditionalAccessTemplate~abc' 300 'oldest'))
        't1.com_ConditionalAccessTemplate~def' = @((& $Event 't1.com_ConditionalAccessTemplate~def' 200 'middle'))
    }
}

Describe 'Get-CIPPBaselineAlignment history reads' {
    BeforeEach {
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        Mock Get-CIPPBaselineDefinition { @([pscustomobject]@{ name = 'ConditionalAccessTemplate'; label = 'CA Template' }) }
        Mock Get-CIPPBaseline { @() }
        Mock Get-CIPPAzDataTableEntity {
            $script:Calls.Add([pscustomobject]@{ TableName = $TableName; Filter = $Filter; First = $First })
            switch ($TableName) {
                'BaselineAlignment' {
                    @(
                        [pscustomobject]@{ PartitionKey = 't1.com'; RowKey = 'ConditionalAccessTemplate~abc'; StandardName = 'ConditionalAccessTemplate#abc'; Status = 'Drift' }
                        [pscustomobject]@{ PartitionKey = 't1.com'; RowKey = 'ConditionalAccessTemplate~def'; StandardName = 'ConditionalAccessTemplate#def'; Status = 'Compliant' }
                    )
                }
                'BaselineHistory' {
                    if ($Filter -match "PartitionKey eq '([^']+)'") {
                        $Rows = @($script:HistoryRows[$Matches[1]])
                        if ($First) { $Rows | Select-Object -First $First } else { $Rows }
                    } else {
                        # Range scan: the table returns partition order, not time order.
                        $script:HistoryRows['t1.com_ConditionalAccessTemplate~abc']
                        $script:HistoryRows['t1.com_ConditionalAccessTemplate~def']
                    }
                }
            }
        }
    }

    It 'builds the tenant payload without reading BaselineHistory' {
        $Result = Get-CIPPBaselineAlignment -TenantFilter 't1.com'

        @($Result.rows).Count | Should -Be 2
        @($script:Calls | Where-Object TableName -EQ 'BaselineHistory').Count | Should -Be 0
        $Result.rows[0].PSObject.Properties.Name | Should -Not -Contain 'history'
    }

    It 'reads one sanitized partition per standard, capped at -PageSize' {
        $Result = Get-CIPPBaselineAlignment -TenantFilter 't1.com' -History -Standard 'ConditionalAccessTemplate#abc' -PageSize 1

        $HistoryCall = @($script:Calls | Where-Object TableName -EQ 'BaselineHistory')
        $HistoryCall.Count | Should -Be 1
        $HistoryCall[0].Filter | Should -Be "PartitionKey eq 't1.com_ConditionalAccessTemplate~abc'"
        $HistoryCall[0].First | Should -Be 1
        ($script:Calls | Where-Object TableName -EQ 'BaselineAlignment').Filter | Should -Be "PartitionKey eq 't1.com' and (StandardName eq 'ConditionalAccessTemplate#abc')"
        @($Result.events).runId | Should -Be @('newest')
        $Result.events[0].standardName | Should -Be 'ConditionalAccessTemplate#abc'
    }

    It 'merges several standards newest-first and applies -PageSize across them' {
        $Result = Get-CIPPBaselineAlignment -TenantFilter 't1.com' -History -Standard 'ConditionalAccessTemplate#abc', 'ConditionalAccessTemplate#def' -PageSize 2

        @($script:Calls | Where-Object TableName -EQ 'BaselineHistory').Count | Should -Be 2
        @($Result.events).runId | Should -Be @('newest', 'middle')
    }

    It 'returns the range scan in time order, not partition order' {
        $Result = Get-CIPPBaselineAlignment -TenantFilter 't1.com' -History

        $HistoryCall = @($script:Calls | Where-Object TableName -EQ 'BaselineHistory')
        $HistoryCall[0].Filter | Should -Be "PartitionKey ge 't1.com_' and PartitionKey lt 't1.com``'"
        $HistoryCall[0].First | Should -BeNullOrEmpty
        @($Result.events).runId | Should -Be @('newest', 'middle', 'oldest')
    }

    It 'pushes -Since, -Outcome and -Mode into the table filter' {
        $Since = 1700000000
        $null = Get-CIPPBaselineAlignment -TenantFilter 't1.com' -History -Since $Since -Outcome 'Drift', "Denied - Remediation Ordered" -Mode 'run'

        $Bound = '{0:D19}' -f ([DateTime]::MaxValue.Ticks - [DateTimeOffset]::FromUnixTimeSeconds($Since).UtcTicks)
        $HistoryCall = @($script:Calls | Where-Object TableName -EQ 'BaselineHistory')
        $HistoryCall[0].Filter | Should -Be ("PartitionKey ge 't1.com_' and PartitionKey lt 't1.com``' and RowKey lt '$Bound' and (Outcome eq 'Drift' or Outcome eq 'Denied - Remediation Ordered') and (Mode eq 'run')")
    }
}

Describe 'Get-CIPPBaselineAlignment history paging' {
    BeforeAll {
        # Three standards, an event every 7 hours for 60 days; every fifth event drifts.
        $Max = [DateTime]::MaxValue.Ticks
        $Now = [DateTime]::UtcNow
        $script:Store = [System.Collections.Generic.List[object]]::new()
        foreach ($Std in 'A', 'B', 'C') {
            for ($i = 0; $i -lt 205; $i++) {
                $At = $Now.AddHours(-7 * $i).AddMinutes(-[int][char]$Std)
                $RunId = 'run{0}{1}' -f $Std, $i
                $script:Store.Add([pscustomobject]@{
                        PartitionKey = "t1.com_$Std"
                        RowKey       = ('{0:D19}-{1}' -f ($Max - $At.Ticks), $RunId)
                        RunId        = $RunId
                        Mode         = $(if ($i % 2) { 'compare' } else { 'run' })
                        Outcome      = $(if ($i % 5) { 'Compliant' } else { 'Drift' })
                    })
            }
        }
        # Evaluates the filter shapes the function builds, in table (PartitionKey, RowKey) order.
        $script:Query = {
            param($Filter, $First)
            $Rows = $script:Store.Where({
                    $Row = $_
                    if ($Filter -match "PartitionKey eq '([^']+)'" -and $Row.PartitionKey -ne $Matches[1]) { return $false }
                    if ($Filter -match "RowKey gt '([^']+)'" -and [string]::CompareOrdinal($Row.RowKey, $Matches[1]) -le 0) { return $false }
                    if ($Filter -match "RowKey lt '([^']+)'" -and [string]::CompareOrdinal($Row.RowKey, $Matches[1]) -ge 0) { return $false }
                    $Outcomes = @([regex]::Matches($Filter, "Outcome eq '([^']+)'") | ForEach-Object { $_.Groups[1].Value })
                    if ($Outcomes -and $Row.Outcome -notin $Outcomes) { return $false }
                    $Modes = @([regex]::Matches($Filter, "Mode eq '([^']+)'") | ForEach-Object { $_.Groups[1].Value })
                    if ($Modes -and $Row.Mode -notin $Modes) { return $false }
                    $true
                })
            $Sorted = @($Rows | Sort-Object -Property PartitionKey, RowKey)
            if ($First) { $Sorted | Select-Object -First $First } else { $Sorted }
        }
        $script:PageAll = {
            param([hashtable]$Params, [int]$Top)
            $Keys = [System.Collections.Generic.List[string]]::new()
            $After = $null
            for ($Guard = 0; $Guard -lt 500; $Guard++) {
                $Page = Get-CIPPBaselineAlignment -TenantFilter 't1.com' -History @Params -PageSize $Top -After $After
                @($Page.events).Count | Should -BeLessOrEqual $Top
                foreach ($Event in $Page.events) { $Keys.Add($Event.runId) }
                $After = $Page.Metadata.nextLink
                if (-not $After) { break }
            }
            , $Keys.ToArray()
        }
    }
    BeforeEach {
        Mock Get-CIPPBaselineDefinition { @() }
        Mock Get-CIPPAzDataTableEntity {
            if ($TableName -eq 'BaselineHistory') { & $script:Query $Filter $First }
        }
    }

    It 'pages through everything newest-first with no gaps or duplicates (<Name>)' -ForEach @(
        @{ Name = 'all events, dense'; Params = @{}; Top = 25 }
        @{ Name = 'sparse outcome filter'; Params = @{ Outcome = @('Drift') }; Top = 7 }
        @{ Name = 'outcome and mode filter'; Params = @{ Outcome = @('Drift'); Mode = @('run') }; Top = 4 }
        @{ Name = 'since bound'; Params = @{ Since = [DateTimeOffset]::UtcNow.AddDays(-10).ToUnixTimeSeconds() }; Top = 20 }
        @{ Name = 'standard partitions'; Params = @{ Standard = @('A', 'C') }; Top = 9 }
    ) {
        $Expected = @((Get-CIPPBaselineAlignment -TenantFilter 't1.com' -History @Params).events.runId)
        $Paged = & $script:PageAll $Params $Top

        $Expected.Count | Should -BeGreaterThan $Top
        $Paged | Should -Be $Expected
    }
}

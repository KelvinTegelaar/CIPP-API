BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function ConvertTo-CIPPODataFilterValue { param($Value) "$Value" -replace "'", "''" }
    function Get-AzDataTableEntity { param($TableName, $Filter, $Property, $First) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Update-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Baselines/Add-CIPPBaselineHistoryEvent.ps1')

    $script:Print = {
        param($Outcome, $Diff, $Detail)
        $DiffJson = if ($Diff) { ConvertTo-Json -Compress -Depth 100 -InputObject @($Diff) } else { '' }
        [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes("$Outcome|$DiffJson|$Detail")))
    }
}

Describe 'Add-CIPPBaselineHistoryEvent streaks' {
    BeforeEach {
        $script:Latest = [pscustomobject]@{ PartitionKey = 't.com_Std'; RowKey = '2516000000000000000-old'; Fingerprint = (& $script:Print 'Drift' @(@{ property = 'a' }) ''); RunCount = 4; TriggeredBy = 'schedule' }
        Mock Get-AzDataTableEntity { $script:Latest }
        Mock Add-CIPPAzDataTableEntity {}
        Mock Update-CIPPAzDataTableEntity {}
    }

    It 'extends the newest row when a scheduled run repeats it' {
        $Id = Add-CIPPBaselineHistoryEvent -TenantFilter 't.com' -Standard 'Std' -Mode 'run' -TriggeredBy 'schedule' -Outcome 'Drift' -Diff @(@{ property = 'a' }) -RunId 'r5'
        $Id | Should -Be 'r5'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        Should -Invoke Update-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Entity.RowKey -eq '2516000000000000000-old' -and $Entity.RunCount -eq 5 -and $Entity.LastRunId -eq 'r5' -and $Entity.LastRunAt -gt 0 -and $Entity.Count -eq 5
        }
    }

    It 'writes a new row when <Case>' -ForEach @(
        @{ Case = 'the outcome changes'; P = @{ Outcome = 'Compliant'; Diff = @(@{ property = 'a' }) } }
        @{ Case = 'the drifted values change'; P = @{ Outcome = 'Drift'; Diff = @(@{ property = 'b' }) } }
        @{ Case = 'the detail changes'; P = @{ Outcome = 'Drift'; Diff = @(@{ property = 'a' }); Detail = 'Error: throttled' } }
        @{ Case = 'a user ran it'; P = @{ Outcome = 'Drift'; Diff = @(@{ property = 'a' }); TriggeredBy = 'tech@msp.com' } }
        @{ Case = 'it remediated'; P = @{ Outcome = 'Drift'; Diff = @(@{ property = 'a' }); Remediated = $true } }
        @{ Case = 'an alert was sent'; P = @{ Outcome = 'Drift'; Diff = @(@{ property = 'a' }); Alerted = $true } }
        @{ Case = 'it is a one-off run'; P = @{ Outcome = 'Drift'; Diff = @(@{ property = 'a' }); Mode = 'oneoff' } }
        @{ Case = 'it is a triage event'; P = @{ Outcome = 'Drift'; Diff = @(@{ property = 'a' }); Mode = 'triage' } }
    ) {
        $Params = @{ TenantFilter = 't.com'; Standard = 'Std'; Mode = 'run'; TriggeredBy = 'schedule'; RunId = 'r5' }
        foreach ($Key in $P.Keys) { $Params[$Key] = $P[$Key] }
        Add-CIPPBaselineHistoryEvent @Params
        Should -Invoke Update-CIPPAzDataTableEntity -Times 0 -Exactly
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Entity.PartitionKey -eq 't.com_Std' -and $Entity.RowKey -like '*-r5' -and $Entity.RunCount -eq 1 -and $Entity.Fingerprint -eq (& $script:Print $P.Outcome $P.Diff $P.Detail)
        }
    }

    It 'writes a new row when the newest row predates fingerprints' {
        $script:Latest = [pscustomobject]@{ PartitionKey = 't.com_Std'; RowKey = '2516000000000000000-old' }
        Add-CIPPBaselineHistoryEvent -TenantFilter 't.com' -Standard 'Std' -Mode 'compare' -TriggeredBy 'verification' -Outcome 'Drift' -Diff @(@{ property = 'a' }) -RunId 'r5'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly
    }

    It 'never extends a row a user wrote' {
        $script:Latest.TriggeredBy = 'tech@msp.com'
        Add-CIPPBaselineHistoryEvent -TenantFilter 't.com' -Standard 'Std' -Mode 'run' -TriggeredBy 'schedule' -Outcome 'Drift' -Diff @(@{ property = 'a' }) -RunId 'r5'
        Should -Invoke Update-CIPPAzDataTableEntity -Times 0 -Exactly
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly
    }

    It 'writes a new row when the row to extend is gone' {
        Mock Update-CIPPAzDataTableEntity { throw 'ResourceNotFound' }
        Add-CIPPBaselineHistoryEvent -TenantFilter 't.com' -Standard 'Std~1' -Mode 'run' -TriggeredBy 'schedule' -Outcome 'Drift' -Diff @(@{ property = 'a' }) -RunId 'r5'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly
    }

    It 'sanitizes # in instance keys for the partition it reads and writes' {
        $script:Latest = $null
        Add-CIPPBaselineHistoryEvent -TenantFilter 't.com' -Standard 'Std#abc' -Mode 'run' -TriggeredBy 'schedule' -Outcome 'Compliant' -RunId 'r5'
        Should -Invoke Get-AzDataTableEntity -ParameterFilter { $Filter -eq "PartitionKey eq 't.com_Std~abc'" -and $First -eq 1 }
        Should -Invoke Add-CIPPAzDataTableEntity -ParameterFilter { $Entity.PartitionKey -eq 't.com_Std~abc' }
    }
}

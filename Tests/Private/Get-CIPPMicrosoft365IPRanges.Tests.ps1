BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Invoke-CIPPRestMethod { param($Uri, $Method, $TimeoutSec) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPMicrosoft365IPRanges.ps1')
    $script:Service = [pscustomobject]@{ ips = @('40.107.0.0/16', '2603:1036::/36') }
}

Describe 'Get-CIPPMicrosoft365IPRanges' {
    BeforeEach {
        $script:M365IPRanges = $null
        $script:Written = $null
        Mock Add-CIPPAzDataTableEntity { $script:Written = $Entity }
    }

    It 'reads the web service once and keeps the list in the table, so a recycled worker does not refetch' {
        Mock Get-CIPPAzDataTableEntity { }
        Mock Invoke-CIPPRestMethod { @($script:Service, [pscustomobject]@{ ips = @('40.107.0.0/16') }) }
        $Ranges = Get-CIPPMicrosoft365IPRanges
        $Ranges | Should -Be @('40.107.0.0/16', '2603:1036::/36')
        $script:Written.RowKey | Should -Be 'worldwide'
        @($script:Written.JSON | ConvertFrom-Json) | Should -Be @('40.107.0.0/16', '2603:1036::/36')

        # a recycled worker: the memo is gone, the table row is fresh
        $script:M365IPRanges = $null
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ JSON = $script:Written.JSON; Timestamp = [datetimeoffset]::UtcNow.AddHours(-2) } }
        Get-CIPPMicrosoft365IPRanges | Should -Be @('40.107.0.0/16', '2603:1036::/36')
        Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly
    }

    It 'refreshes a day-old copy, and falls back to it when the web service is down' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ JSON = '["13.107.6.152/31"]'; Timestamp = [datetimeoffset]::UtcNow.AddDays(-3) } }
        Mock Invoke-CIPPRestMethod { $script:Service }
        Get-CIPPMicrosoft365IPRanges | Should -Be @('40.107.0.0/16', '2603:1036::/36')

        $script:M365IPRanges = $null
        Mock Invoke-CIPPRestMethod { throw 'endpoints.office.com unreachable' }
        Get-CIPPMicrosoft365IPRanges | Should -Be @('13.107.6.152/31')
        $script:M365IPRanges.Expires | Should -BeLessThan ([datetime]::UtcNow.AddMinutes(15)) -Because 'a stale copy is retried soon'
    }

    It 'throws when there is neither a list nor a cached copy' {
        Mock Get-CIPPAzDataTableEntity { }
        Mock Invoke-CIPPRestMethod { throw 'endpoints.office.com unreachable' }
        { Get-CIPPMicrosoft365IPRanges } | Should -Throw '*unreachable*'
    }
}

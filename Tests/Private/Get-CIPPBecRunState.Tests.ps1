# A 'z-<Value>' run-state row (the raw mail records) can be tens of MB, so only a phase that names
# the value may download it; every other read, Score's unnamed read included, must leave it alone.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    function Get-CIPPTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecRunState.ps1')
}

Describe 'Get-CIPPBecRunState' {
    BeforeEach {
        Mock Get-CIPPAzDataTableEntity {
            @(
                [pscustomobject]@{ RowKey = '00-Run'; Data = '{"UserName":"adele@contoso.com"}' }
                [pscustomobject]@{ RowKey = 'z-MailRecords'; Data = '{"MailRecords":[{"Operation":"Send"}]}' }
            ).Where({ $Filter -match "RowKey eq '$($_.RowKey)'" -or $_.RowKey -lt 'z' })
        }
    }

    It 'reads the mail records only when they are named' {
        $State = Get-CIPPBecRunState -CaseId 'case-1' -Name 'UserName', 'MailRecords'
        $State.MailRecords[0].Operation | Should -Be 'Send'
        $State.UserName | Should -Be 'adele@contoso.com'
    }

    It 'leaves them out of <Name>' -ForEach @(
        @{ Name = 'an unnamed read'; Names = $null }
        @{ Name = 'a read that names other values'; Names = @('UserName', 'MailActivity') }
    ) {
        $State = if ($Names) { Get-CIPPBecRunState -CaseId 'case-1' -Name $Names } else { Get-CIPPBecRunState -CaseId 'case-1' }
        $State.ContainsKey('MailRecords') | Should -BeFalse
        $State.UserName | Should -Be 'adele@contoso.com'
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Filter -notmatch 'z-MailRecords' }
    }
}

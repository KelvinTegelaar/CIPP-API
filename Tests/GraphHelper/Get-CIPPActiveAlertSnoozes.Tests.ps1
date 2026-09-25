# Pester tests for Get-CIPPActiveAlertSnoozes.
# Timed snoozes are active until their SnoozeUntil passes; "until resolved" snoozes are always
# active; rows with no usable expiry (the old -1 "forever" value included) are treated as lapsed
# and cleaned up rather than muting an alert indefinitely.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $TableName, $Filter, $Property) }
    function Remove-CIPPAzDataTableEntity { param($Context, $TableName, $Entity, [switch]$Force) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPActiveAlertSnoozes.ps1')

    function New-Snooze {
        param($Hash, $SnoozeUntil, $UntilResolved = 'False')
        [pscustomobject]@{
            PartitionKey  = 'Get-CIPPAlertSomething'
            RowKey        = "contoso.onmicrosoft.com-$Hash"
            Tenant        = 'contoso.onmicrosoft.com'
            ContentHash   = $Hash
            SnoozeUntil   = [string]$SnoozeUntil
            UntilResolved = $UntilResolved
        }
    }
}

Describe 'Get-CIPPActiveAlertSnoozes' {
    BeforeEach {
        $script:Removed = [System.Collections.Generic.List[object]]::new()
        Mock Get-CIPPTable { @{ TableName = 'AlertSnooze' } }
        Mock ConvertTo-CIPPODataFilterValue { $Value }
        Mock Remove-CIPPAzDataTableEntity { $script:Removed.Add($Entity) }
    }

    It 'keeps timed snoozes that have not expired and until-resolved snoozes' {
        $Now = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
        Mock Get-CIPPAzDataTableEntity {
            @(
                (New-Snooze -Hash 'future' -SnoozeUntil ($Now + 86400)),
                (New-Snooze -Hash 'past' -SnoozeUntil ($Now - 3600)),
                (New-Snooze -Hash 'untilresolved' -SnoozeUntil 0 -UntilResolved 'True')
            )
        }

        $Active = Get-CIPPActiveAlertSnoozes -CmdletName 'Get-CIPPAlertSomething' -TenantFilter 'contoso.onmicrosoft.com'

        $Active.Keys | Should -Contain 'future'
        $Active.Keys | Should -Contain 'untilresolved'
        $Active.Keys | Should -Not -Contain 'past'
        $script:Removed.Count | Should -Be 0
    }

    It 'treats the legacy forever value as lapsed and removes it' {
        Mock Get-CIPPAzDataTableEntity { @(New-Snooze -Hash 'forever' -SnoozeUntil -1) }

        $Active = Get-CIPPActiveAlertSnoozes -CmdletName 'Get-CIPPAlertSomething' -TenantFilter 'contoso.onmicrosoft.com'

        $Active.Count | Should -Be 0
        $script:Removed.Count | Should -Be 1
        $script:Removed[0].RowKey | Should -Be 'contoso.onmicrosoft.com-forever'
    }

    It 'removes timed snoozes that expired more than 30 days ago' {
        $Now = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
        Mock Get-CIPPAzDataTableEntity { @(New-Snooze -Hash 'ancient' -SnoozeUntil ($Now - 40 * 86400)) }

        $Active = Get-CIPPActiveAlertSnoozes -CmdletName 'Get-CIPPAlertSomething' -TenantFilter 'contoso.onmicrosoft.com'

        $Active.Count | Should -Be 0
        $script:Removed.Count | Should -Be 1
    }

    It 'ignores rows for other tenants' {
        $Now = [int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
        Mock Get-CIPPAzDataTableEntity {
            $Row = New-Snooze -Hash 'other' -SnoozeUntil ($Now + 86400)
            $Row.Tenant = 'fabrikam.onmicrosoft.com'
            @($Row)
        }

        $Active = Get-CIPPActiveAlertSnoozes -CmdletName 'Get-CIPPAlertSomething' -TenantFilter 'contoso.onmicrosoft.com'

        $Active.Count | Should -Be 0
    }
}

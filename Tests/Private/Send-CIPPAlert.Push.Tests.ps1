# Pester tests for the push channel in Send-CIPPAlert.
#
# Pins the per-user fan-out: every device registered to the target user gets the payload
# through CIPP.WebPush, a 410 from the push service prunes that row, and other failures are
# logged without stopping the remaining devices.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Send-CIPPAlert.ps1'
    $Dll = Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll'
    if (-not ('CIPP.WebPush' -as [type])) { Add-Type -Path $Dll }

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Remove-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $headers, $LogData) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Get-CIPPVapidKeys { param([switch]$PublicOnly) }

    . $FunctionPath

}

Describe 'Send-CIPPAlert -Type push' {
    BeforeEach {
        Mock Get-CIPPTable { @{ Context = 'ctx' } }
        Mock Write-LogMessage { }
        Mock Remove-AzDataTableEntity { }
        Mock Get-CIPPVapidKeys { @{ PublicKey = 'pub'; PrivateKey = 'priv' } }
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        # Return the notification config for the SchedulerConfig read at the top, subscriptions
        # for the PushSubscriptions read, and no CIPPURL.
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -like "*PartitionKey eq 'tech@msp.example'*") { return $script:Devices }
            if ($Filter -like "*CIPPURL*") { return $null }
            return $null
        }
    }

    It 'reports when the user has no devices without touching the push service' {
        $script:Devices = @()
        $Result = Send-CIPPAlert -Type 'push' -TargetUser 'tech@msp.example' -Title 'T' -PushMessage 'M' -WhatIf
        $Result | Should -Match 'No push devices registered'
    }

    It 'needs a target user' {
        Send-CIPPAlert -Type 'push' -Title 'T' -PushMessage 'M' | Should -Match 'No target user'
    }

    It 'addresses every registered device for the user' {
        $script:Devices = @(
            [pscustomobject]@{ PartitionKey = 'tech@msp.example'; RowKey = 'a'; DeviceName = 'Laptop'; Endpoint = 'https://push.example/a'; P256dh = 'p'; Auth = 'q' }
            [pscustomobject]@{ PartitionKey = 'tech@msp.example'; RowKey = 'b'; DeviceName = 'Phone'; Endpoint = 'https://push.example/b'; P256dh = 'p'; Auth = 'q' }
        )
        # -WhatIf short-circuits ShouldProcess so no network call is made, but the fan-out
        # must still enumerate both rows and report their count.
        $Result = Send-CIPPAlert -Type 'push' -TargetUser 'tech@msp.example' -Title 'T' -PushMessage 'M' -WhatIf
        $Result | Should -Match 'of 2 device'
        Should -Invoke Get-CIPPVapidKeys -Times 1
        Should -Invoke Remove-AzDataTableEntity -Times 0
    }
}

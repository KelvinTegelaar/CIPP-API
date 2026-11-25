# Pester tests for Close-CippExtAlertTicket: closing the consolidated PSA ticket an alert task raised
# once the alert has cleared on two clean runs in a row.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPTable { param([string]$TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Update-CIPPAzDataTableEntity { param($TableName, $Entity) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Get-Tenants { param($TenantFilter) }
    function Get-StringHash { param($String) }
    function Get-HaloToken { param($configuration) }
    function Get-NinjaOneUserToken { }
    function Get-CippUserAgent { }
    function Get-NormalizedError { param($Message) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function ConvertTo-NinjaOnePlainText { param([string]$Html) $Html }

    . (Join-Path $BackendRoot 'Modules/CippExtensions/Public/Close-CippExtAlertTicket.ps1')

    function Set-Scenario {
        param(
            [hashtable]$Halo = @{},
            [hashtable]$Ninja = $null,
            $Row = @{ PartitionKey = 'HaloPSA'; RowKey = '5-hash'; TicketID = 1234; ClearRuns = 1 },
            [bool]$Closed = $false
        )
        $HaloConfig = @{ Enabled = $true; ConsolidateTickets = $true; CloseResolvedTickets = $true; ResourceURL = 'https://halo.example/api'; CloseOutcome = @{ label = 'Close'; value = 88 } }
        foreach ($Key in $Halo.Keys) { $HaloConfig[$Key] = $Halo[$Key] }
        $Config = @{ HaloPSA = $HaloConfig }
        if ($Ninja) { $Config = @{ NinjaOne = $Ninja } }
        $script:ConfigRow = [pscustomobject]@{ config = ($Config | ConvertTo-Json -Depth 5) }
        $script:TicketRow = if ($Row) { [pscustomobject]$Row } else { $null }
        $script:TicketClosed = $Closed
    }
}

Describe 'Close-CippExtAlertTicket' {
    BeforeEach {
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        $script:FailPost = $false
        Mock Get-CIPPTable { param([string]$TableName) @{ TableName = $TableName } }
        Mock Get-CIPPAzDataTableEntity {
            param($TableName, $Filter)
            switch ($TableName) {
                'Extensionsconfig' { $script:ConfigRow }
                'CippMapping' { [pscustomobject]@{ IntegrationId = '5' } }
                'PSATickets' { $script:TicketRow }
            }
        }
        Mock Get-Tenants { [pscustomobject]@{ customerId = 'tenant-guid' } }
        Mock Get-StringHash { 'hash' }
        Mock Get-HaloToken { @{ access_token = 'token' } }
        Mock Get-NinjaOneUserToken { @{ access_token = 'token' } }
        Mock Get-CippUserAgent { 'CIPP' }
        Mock Get-NormalizedError { param($Message) $Message }
        Mock Get-CippException { @{} }
        Mock Update-CIPPAzDataTableEntity { }
        Mock Remove-CIPPAzDataTableEntity { }
        Mock Write-LogMessage { }
        Mock Invoke-RestMethod {
            param($Uri, $Method, $Body)
            $script:Calls.Add([pscustomobject]@{ Uri = $Uri; Method = $Method; Body = $Body })
            if ($Method -eq 'Get') {
                if ($Uri -like '*/ticketing/*') {
                    $Status = if ($script:TicketClosed) { @{ name = 'CLOSED'; parentId = 6000 } } else { @{ name = 'OPEN'; parentId = 2000 } }
                    return [pscustomobject]@{ id = 77; version = 3; clientId = 9; ticketFormId = 2; subject = 'Alert'; status = $Status }
                }
                return [pscustomobject]@{ id = 1234; hasbeenclosed = $script:TicketClosed }
            }
            if ($script:FailPost) { throw 'HTTP 400 Bad Request' }
            @{}
        }
    }

    It 'does nothing when the switch is off' {
        Set-Scenario -Halo @{ CloseResolvedTickets = $false }
        Close-CippExtAlertTicket -TenantFilter 'contoso.com' -ConsolidationKey 'contoso.com|task1' -AlertName 'MFA' -ResolvedCount 0
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'marks the ticket on the run that resolves the last items, without closing it' {
        Set-Scenario -Row @{ PartitionKey = 'HaloPSA'; RowKey = '5-hash'; TicketID = 1234 }
        Close-CippExtAlertTicket -TenantFilter 'contoso.com' -ConsolidationKey 'contoso.com|task1' -AlertName 'MFA' -ResolvedCount 2
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
        Should -Invoke Update-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $TableName -eq 'PSATickets' -and $Entity.RowKey -eq '5-hash' -and $Entity.ClearRuns -eq 1 }
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $TableName -eq 'PSATickets' -and $Filter -eq "PartitionKey eq 'HaloPSA' and RowKey eq '5-hash'" }
    }

    It 'leaves a ticket alone on a clean run that was never marked' {
        Set-Scenario -Row @{ PartitionKey = 'HaloPSA'; RowKey = '5-hash'; TicketID = 1234 }
        Close-CippExtAlertTicket -TenantFilter 'contoso.com' -ConsolidationKey 'contoso.com|task1' -AlertName 'MFA' -ResolvedCount 0
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'closes a marked HaloPSA ticket once with the close outcome and a note, then forgets it' {
        Set-Scenario
        Close-CippExtAlertTicket -TenantFilter 'contoso.com' -ConsolidationKey 'contoso.com|task1' -AlertName 'MFA <admins>' -ResolvedCount 0
        $Post = @($script:Calls | Where-Object { $_.Method -eq 'Post' })
        $Post.Count | Should -Be 1
        $Post[0].Uri | Should -Be 'https://halo.example/api/actions'
        $Action = @($Post[0].Body | ConvertFrom-Json)[0]
        $Action.ticket_id | Should -Be 1234
        $Action.outcome_id | Should -Be 88
        $Action.sendemail | Should -BeFalse
        $Action.note_html | Should -Match 'MFA &lt;admins&gt;'
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Info' -and $message -like 'Closed HaloPSA ticket 1234*' }

        $script:TicketRow = $null
        Close-CippExtAlertTicket -TenantFilter 'contoso.com' -ConsolidationKey 'contoso.com|task1' -AlertName 'MFA' -ResolvedCount 0
        @($script:Calls | Where-Object { $_.Method -eq 'Post' }).Count | Should -Be 1
    }

    It 'leaves a HaloPSA ticket someone already closed and forgets it' {
        Set-Scenario -Closed $true
        Close-CippExtAlertTicket -TenantFilter 'contoso.com' -ConsolidationKey 'contoso.com|task1' -AlertName 'MFA' -ResolvedCount 0
        @($script:Calls | Where-Object { $_.Method -eq 'Post' }).Count | Should -Be 0
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $message -like '*already closed*' }
    }

    It 'leaves per-user and other tickets alone because they are stored under a different key' {
        Set-Scenario -Row $null
        Close-CippExtAlertTicket -TenantFilter 'contoso.com' -ConsolidationKey 'contoso.com|task1' -AlertName 'MFA' -ResolvedCount 0
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
        Should -Invoke Update-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'logs a failed close, keeps the ticket for the next run, and does not throw' {
        Set-Scenario
        $script:FailPost = $true
        { Close-CippExtAlertTicket -TenantFilter 'contoso.com' -ConsolidationKey 'contoso.com|task1' -AlertName 'MFA' -ResolvedCount 0 } | Should -Not -Throw
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like 'Could not close HaloPSA ticket 1234*try again*' }
    }

    It 'does not throw when the configuration cannot be read' {
        Mock Get-CIPPAzDataTableEntity { throw 'table offline' }
        { Close-CippExtAlertTicket -TenantFilter 'contoso.com' -ConsolidationKey 'contoso.com|task1' -AlertName 'MFA' -ResolvedCount 0 } | Should -Not -Throw
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' }
    }

    It 'asks for a close outcome instead of guessing one' {
        Set-Scenario -Halo @{ CloseOutcome = $null }
        Close-CippExtAlertTicket -TenantFilter 'contoso.com' -ConsolidationKey 'contoso.com|task1' -AlertName 'MFA' -ResolvedCount 0
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $message -like '*Close Outcome*' }
    }

    It 'comments on a marked NinjaOne ticket and sets it to Resolved with its own fields' {
        Set-Scenario -Ninja @{ Enabled = $true; TicketingEnabled = $true; ConsolidateTickets = $true; CloseResolvedTickets = $true; Instance = 'eu.ninjarmm.com' } -Row @{ PartitionKey = 'NinjaOne'; RowKey = '5-hash'; TicketID = 77; ClearRuns = 1 }
        Close-CippExtAlertTicket -TenantFilter 'contoso.com' -ConsolidationKey 'contoso.com|task1' -AlertName 'MFA' -ResolvedCount 0
        @($script:Calls | Where-Object { $_.Uri -eq 'https://eu.ninjarmm.com/api/v2/ticketing/ticket/77/comment' -and $_.Method -eq 'POST' }).Count | Should -Be 1
        $Put = @($script:Calls | Where-Object { $_.Method -eq 'PUT' })
        $Put.Count | Should -Be 1
        $Update = $Put[0].Body | ConvertFrom-Json
        ($Update.status, $Update.version, $Update.clientId, $Update.ticketFormId, $Update.subject) | Should -Be @('5000', 3, 9, 2, 'Alert')
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly
    }

    It 'leaves a NinjaOne ticket someone already closed' {
        Set-Scenario -Ninja @{ Enabled = $true; TicketingEnabled = $true; ConsolidateTickets = $true; CloseResolvedTickets = $true; Instance = 'eu.ninjarmm.com' } -Row @{ PartitionKey = 'NinjaOne'; RowKey = '5-hash'; TicketID = 77; ClearRuns = 1 } -Closed $true
        Close-CippExtAlertTicket -TenantFilter 'contoso.com' -ConsolidationKey 'contoso.com|task1' -AlertName 'MFA' -ResolvedCount 0
        @($script:Calls | Where-Object { $_.Method -ne 'GET' }).Count | Should -Be 0
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly
    }
}

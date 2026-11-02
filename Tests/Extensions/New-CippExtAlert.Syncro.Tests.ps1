# Pester tests for the Syncro branch of New-CippExtAlert.
# The dispatcher resolves the tenant to its mapped Syncro customer and hands the alert to
# New-SyncroPSATicket. Syncro has no safe default customer (HaloPSA falls back to client 1), so an
# unmapped tenant has to come back as a Failed line that Send-CIPPAlert reports, not a ticket on
# whichever customer happens to have id 1.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CippExtensions/Public/New-CippExtAlert.ps1'

    function Get-CIPPTable { param([string]$TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property, $First) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function New-HaloPSATicket { param($Title, $Description, $Client, $UserUPN, $AzureOID, $DisplayName, $TicketId, $TicketPriority, $ConsolidationKey) }
    function New-SyncroPSATicket { param($Title, $Description, $Client, $TicketPriority) }
    function New-GradientAlert { param($Title, $Description, $Client) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData, $headers) }

    . $FunctionPath

    function New-Alert {
        param($PsaTicketPriority)
        $Alert = [pscustomobject]@{
            TenantId   = 'contoso.onmicrosoft.com'
            AlertTitle = '[CIPP] Alert'
            AlertText  = '<p>body</p>'
        }
        if ($PsaTicketPriority) { $Alert | Add-Member -NotePropertyName PsaTicketPriority -NotePropertyValue $PsaTicketPriority }
        $Alert
    }

    # The mock body runs in its own scope, so the switches are copied to script scope first;
    # referencing the function parameters directly from the mock would always read $false.
    function Set-ConfigMocks {
        param([switch]$Mapped, [switch]$HaloToo)
        $script:SyncroMapped = [bool]$Mapped
        $script:HaloEnabledToo = [bool]$HaloToo
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($TableName, $Filter)
            if ($Filter -like '*SyncroMapping*') {
                if ($script:SyncroMapped) { return [pscustomobject]@{ RowKey = 'customer-guid'; IntegrationId = '42'; IntegrationName = 'Contoso Ltd' } }
                return $null
            }
            if ($Filter -like '*HaloMapping*') { return [pscustomobject]@{ RowKey = 'customer-guid'; IntegrationId = 7 } }
            $Config = @{ Syncro = @{ enabled = $true } }
            if ($script:HaloEnabledToo) { $Config.HaloPSA = @{ enabled = $true } }
            [pscustomobject]@{ config = ($Config | ConvertTo-Json -Depth 5) }
        }
    }
}

Describe 'New-CippExtAlert - Syncro' {
    BeforeEach {
        $script:TicketArgs = $null
        Mock -CommandName Get-CIPPTable -MockWith { param([string]$TableName) @{ TableName = $TableName } }
        Mock -CommandName Get-Tenants -MockWith { [pscustomobject]@{ customerId = 'customer-guid' } }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName New-HaloPSATicket -MockWith { 'Ticket created in HaloPSA: 1' }
        Mock -CommandName New-SyncroPSATicket -MockWith {
            param($Title, $Description, $Client, $TicketPriority)
            $script:TicketArgs = [pscustomobject]@{ Title = $Title; Description = $Description; Client = $Client; TicketPriority = $TicketPriority }
            'Ticket created in Syncro: #2012 (id 987)'
        }
    }

    It 'raises the ticket against the mapped Syncro customer' {
        Set-ConfigMocks -Mapped

        $Result = New-CippExtAlert -Alert (New-Alert)

        $script:TicketArgs.Client | Should -Be '42'
        $script:TicketArgs.Title | Should -Be '[CIPP] Alert'
        $script:TicketArgs.Description | Should -Be '<p>body</p>'
        $Result | Should -Be 'Ticket created in Syncro: #2012 (id 987)'
    }

    It 'passes the per-alert priority through' {
        Set-ConfigMocks -Mapped

        New-CippExtAlert -Alert (New-Alert -PsaTicketPriority '1 High') | Out-Null

        $script:TicketArgs.TicketPriority | Should -Be '1 High'
    }

    It 'leaves the priority unset when the alert carries none' {
        Set-ConfigMocks -Mapped

        New-CippExtAlert -Alert (New-Alert) | Out-Null

        $script:TicketArgs.TicketPriority | Should -BeNullOrEmpty
    }

    It 'reports an unmapped tenant as a failure instead of guessing a customer' {
        Set-ConfigMocks

        $Result = New-CippExtAlert -Alert (New-Alert)

        Should -Invoke New-SyncroPSATicket -Times 0 -Exactly
        $Result | Should -BeLike 'Failed to send ticket to Syncro: No Syncro customer mapping for tenant contoso.onmicrosoft.com*'
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' -and $API -eq 'SyncroTicket' -and $tenant -eq 'contoso.onmicrosoft.com' }
    }

    It 'does not touch HaloPSA when only Syncro is enabled' {
        Set-ConfigMocks -Mapped

        New-CippExtAlert -Alert (New-Alert) | Out-Null

        Should -Invoke New-HaloPSATicket -Times 0 -Exactly
    }

    It 'raises in both PSAs when both are enabled' {
        Set-ConfigMocks -Mapped -HaloToo

        $Result = @(New-CippExtAlert -Alert (New-Alert))

        Should -Invoke New-HaloPSATicket -Times 1 -Exactly
        Should -Invoke New-SyncroPSATicket -Times 1 -Exactly
        $Result | Should -Contain 'Ticket created in Syncro: #2012 (id 987)'
        $Result | Should -Contain 'Ticket created in HaloPSA: 1'
    }
}

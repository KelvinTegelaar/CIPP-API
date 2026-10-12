# Pester tests for adopting title-keyed HaloPSA consolidation rows once a caller supplies a
# stable ConsolidationKey, so changing an alert title does not fork an open ticket.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CippExtensions/Public/Halo/New-HaloPSATicket.ps1'

    function Get-CIPPTable { param([string]$TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property, $First) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Get-HaloToken { param($configuration) }
    function Get-CippUserAgent { 'CIPP/test' }
    function Get-HaloUser { param($AzureOID, $Email, $ClientId, $Configuration, $Token) }
    function Get-StringHash { param($String) }
    function Get-NormalizedError { param($Message) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData, $headers) }

    . $FunctionPath
}

Describe 'New-HaloPSATicket - legacy title row migration' {
    BeforeEach {
        $script:NewRow = $null
        $script:LegacyRow = $null
        $script:HaloTicketClosed = $false
        $script:Added = [System.Collections.Generic.List[object]]::new()
        $script:Removed = [System.Collections.Generic.List[object]]::new()
        $script:NotedTicket = $null

        Mock -CommandName Get-CIPPTable -MockWith { param([string]$TableName) @{ TableName = $TableName } }
        Mock -CommandName Get-HaloToken -MockWith { @{ access_token = 'token' } }
        Mock -CommandName Get-HaloUser -MockWith { $null }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-StringHash -MockWith {
            param($String)
            if ($String -eq 'contoso.com|task-1') { 'newhash' } else { 'legacyhash' }
        }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { param($TableName, $Entity) $script:Added.Add($Entity) }
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith { param($TableName, $Entity) $script:Removed.Add($Entity) }

        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($TableName, $Filter)
            if ($Filter -like "*'19-newhash'*") { return $script:NewRow }
            if ($Filter -like "*'19-legacyhash'*") { return $script:LegacyRow }
            if ($Filter) { return $null }
            [pscustomobject]@{
                config = (@{
                        HaloPSA = @{
                            Enabled            = $true
                            ResourceURL        = 'https://halo.example.com/api'
                            ConsolidateTickets = $true
                            LinkTicketsToUsers = $false
                        }
                    } | ConvertTo-Json -Depth 5)
            }
        }

        Mock -CommandName Invoke-RestMethod -MockWith {
            param($Uri, $ContentType, $Method, $Body, $Headers, [switch]$SkipHttpErrorCheck)
            if ($Method -eq 'Get') {
                return @{ id = ($Uri -replace '.*/Tickets/(\d+)\?.*', '$1'); hasbeenclosed = $script:HaloTicketClosed }
            }
            if ($Uri -like '*/actions') {
                $script:NotedTicket = ($Body | ConvertFrom-Json)[0].ticket_id
                return @{ id = 5555 }
            }
            return @{ id = 1000 }
        }

        $script:TicketArgs = @{
            title            = 'Alert - contoso.com - Reworded title'
            description      = '<p>body</p>'
            client           = 19
            ConsolidationKey = 'contoso.com|task-1'
        }
    }

    It 'adds a note on a direct key hit without re-keying' {
        $script:NewRow = [pscustomobject]@{ PartitionKey = 'HaloPSA'; RowKey = '19-newhash'; TicketID = 111 }

        $Result = New-HaloPSATicket @script:TicketArgs

        $Result | Should -Be 'Note added to ticket in HaloPSA: 111'
        $script:Added.Count | Should -Be 0
        $script:Removed.Count | Should -Be 0
    }

    It 'adopts an open legacy title-keyed ticket and moves its row to the stable key' {
        $script:LegacyRow = [pscustomobject]@{ PartitionKey = 'HaloPSA'; RowKey = '19-legacyhash'; Title = 'Old title'; ClientId = 19; TicketID = 222 }

        $Result = New-HaloPSATicket @script:TicketArgs

        $Result | Should -Be 'Note added to ticket in HaloPSA: 222'
        $script:NotedTicket | Should -Be 222
        $script:Added.Count | Should -Be 1
        $script:Added[0].RowKey | Should -Be '19-newhash'
        $script:Added[0].TicketID | Should -Be 222
        $script:Added[0].ClientId | Should -Be 19
        $script:Added[0].Title | Should -Be 'Old title'
        $script:Removed.Count | Should -Be 1
        $script:Removed[0].RowKey | Should -Be '19-legacyhash'
    }

    It 'leaves a closed legacy ticket alone and stores the new ticket under the stable key' {
        $script:LegacyRow = [pscustomobject]@{ PartitionKey = 'HaloPSA'; RowKey = '19-legacyhash'; Title = 'Old title'; ClientId = 19; TicketID = 222 }
        $script:HaloTicketClosed = $true

        $Result = New-HaloPSATicket @script:TicketArgs

        $Result | Should -Be 'Ticket created in HaloPSA: 1000'
        $script:Removed.Count | Should -Be 0
        $script:Added.Count | Should -Be 1
        $script:Added[0].RowKey | Should -Be '19-newhash'
        $script:Added[0].TicketID | Should -Be 1000
    }

    It 'does not look up a legacy row when no key is supplied' {
        $script:TicketArgs.Remove('ConsolidationKey')

        $Result = New-HaloPSATicket @script:TicketArgs

        $Result | Should -Be 'Ticket created in HaloPSA: 1000'
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Filter }
        $script:Removed.Count | Should -Be 0
    }
}

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity { param($Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Entity, [switch]$Force) }
    function Get-HaloToken { param($configuration) }
    function Get-CippUserAgent { 'CIPP/test' }
    function Get-HaloTicketTypeSlaId { param($TicketType, $Configuration, $Token) }
    function Get-HaloUser { param($AzureOID, $Email, $ClientId, $Configuration, $Token) }
    function Get-StringHash { param($String) }
    function Get-NormalizedError { param($Message) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }

    . (Join-Path $RepoRoot 'Modules/CippExtensions/Public/Halo/New-HaloPSATicket.ps1')

    # Rebuilds the Extensionsconfig row the function reads on every call. DefaultPriority is the
    # integration-wide setting; the per-alert override arrives as the -TicketPriority parameter.
    function New-HaloConfigRow {
        param($DefaultPriority, [switch]$ConsolidateTickets)
        $Halo = @{
            ResourceURL        = 'https://halo.example.com/api'
            TicketType         = 1
            ConsolidateTickets = [bool]$ConsolidateTickets
        }
        if ($PSBoundParameters.ContainsKey('DefaultPriority')) { $Halo.DefaultPriority = $DefaultPriority }
        [pscustomobject]@{ config = (@{ HaloPSA = $Halo } | ConvertTo-Json -Depth 5 -Compress) }
    }

    # The ticket payload is only observable as the JSON body handed to Invoke-RestMethod.
    function Get-SentTicket {
        param($Body)
        @($Body | ConvertFrom-Json)[0]
    }
}

Describe 'New-HaloPSATicket priority resolution' {
    BeforeEach {
        $script:SentBody = $null

        Mock Get-CIPPTable { @{} }
        Mock Get-HaloToken { @{ access_token = 'token' } }
        # Ticket type has an SLA unless a test says otherwise - priority is only sent when one is
        # attached, because a priority id is meaningless outside the SLA that defines it.
        Mock Get-HaloTicketTypeSlaId { 1 }
        Mock Get-StringHash { 'hash' }
        Mock Add-CIPPAzDataTableEntity {}
        Mock Write-LogMessage {}
        Mock Invoke-RestMethod {
            $script:SentBody = $Body
            @{ id = 42 }
        }
    }

    Context 'when creating a new ticket' {
        BeforeEach {
            Mock Get-CIPPAzDataTableEntity { New-HaloConfigRow -DefaultPriority 3 }
        }

        It 'uses the per-alert priority over the integration default' {
            $null = New-HaloPSATicket -title 'Alert' -description 'Body' -client 1 -TicketPriority 5

            (Get-SentTicket -Body $script:SentBody).priority_id | Should -Be 5
        }

        It 'unwraps the {label, value} shape saved by the alert form' {
            $null = New-HaloPSATicket -title 'Alert' -description 'Body' -client 1 -TicketPriority @{ label = 'Critical'; value = 5 }

            (Get-SentTicket -Body $script:SentBody).priority_id | Should -Be 5
        }

        It 'falls back to the integration default when no per-alert priority is set' {
            $null = New-HaloPSATicket -title 'Alert' -description 'Body' -client 1

            (Get-SentTicket -Body $script:SentBody).priority_id | Should -Be 3
        }

        It 'falls back to the integration default when the per-alert value is empty' {
            $null = New-HaloPSATicket -title 'Alert' -description 'Body' -client 1 -TicketPriority ''

            (Get-SentTicket -Body $script:SentBody).priority_id | Should -Be 3
        }

        It 'falls back and warns when the per-alert value is a hint row' {
            # -1 is the id Get-HaloPriority uses for its explanatory rows. It casts to a truthy
            # int, so only the -gt 0 guard keeps it out of the payload.
            $null = New-HaloPSATicket -title 'Alert' -description 'Body' -client 1 -TicketPriority -1

            (Get-SentTicket -Body $script:SentBody).priority_id | Should -Be 3
            Should -Invoke Write-LogMessage -Times 1 -ParameterFilter {
                $sev -eq 'Warning' -and $message -like "*from alert is not a valid priority id*"
            }
        }
    }

    Context 'when the ticket type has no SLA' {
        BeforeEach {
            Mock Get-CIPPAzDataTableEntity { New-HaloConfigRow -DefaultPriority 3 }
            Mock Get-HaloTicketTypeSlaId { $null }
        }

        It 'omits priority_id even when the alert asks for one' {
            # A priority id resolves against an SLA, so with none attached there is nothing for it
            # to mean. Halo applies its own priority instead of us gambling on the SLA it picks.
            $null = New-HaloPSATicket -title 'Alert' -description 'Body' -client 1 -TicketPriority 5

            (Get-SentTicket -Body $script:SentBody).PSObject.Properties.Name | Should -Not -Contain 'priority_id'
        }

        It 'omits priority_id when only the integration default is set' {
            $null = New-HaloPSATicket -title 'Alert' -description 'Body' -client 1

            (Get-SentTicket -Body $script:SentBody).PSObject.Properties.Name | Should -Not -Contain 'priority_id'
        }

        It 'does not look up the SLA when there is no priority to send' {
            Mock Get-CIPPAzDataTableEntity { New-HaloConfigRow }

            $null = New-HaloPSATicket -title 'Alert' -description 'Body' -client 1

            Should -Invoke Get-HaloTicketTypeSlaId -Times 0
        }
    }

    Context 'when neither priority is configured' {
        BeforeEach {
            Mock Get-CIPPAzDataTableEntity { New-HaloConfigRow }
        }

        It 'omits priority_id entirely and logs nothing' {
            $null = New-HaloPSATicket -title 'Alert' -description 'Body' -client 1

            $Ticket = Get-SentTicket -Body $script:SentBody
            $Ticket.PSObject.Properties.Name | Should -Not -Contain 'priority_id'
            Should -Invoke Write-LogMessage -Times 0
        }
    }

    Context 'when consolidating onto an existing open ticket' {
        BeforeEach {
            Mock Get-CIPPAzDataTableEntity -ParameterFilter { $Filter } { [pscustomobject]@{ TicketID = 99 } }
            Mock Get-CIPPAzDataTableEntity -ParameterFilter { -not $Filter } { New-HaloConfigRow -DefaultPriority 3 -ConsolidateTickets }
            Mock Invoke-RestMethod -ParameterFilter { $Method -eq 'Get' } { @{ id = 99; hasbeenclosed = $false } }
            Mock Invoke-RestMethod -ParameterFilter { $Method -eq 'Post' } {
                $script:SentBody = $Body
                @{ id = 100 }
            }
        }

        It 'leaves the existing ticket priority alone' {
            # Priority is deliberately create-path only - appending a note must not overwrite a
            # priority a technician has since changed on the ticket.
            $Result = New-HaloPSATicket -title 'Alert' -description 'Body' -client 1 -TicketPriority 5

            $Result | Should -BeLike 'Note added to ticket in HaloPSA*'
            (Get-SentTicket -Body $script:SentBody).PSObject.Properties.Name | Should -Not -Contain 'priority_id'
        }
    }
}

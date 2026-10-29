# Pester tests for the Syncro ticket payload built by New-SyncroPSATicket.
# Syncro wants its four priorities spelled exactly as it stores them ('1 High', not 'High' or 1),
# and the per-alert priority on an alert may be a HaloPSA id when both PSAs are enabled, so the
# resolution order and what is rejected both matter. The body is only observable as the JSON
# handed to Invoke-SyncroRequest.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPTable { param([string]$TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property, $First) }
    function Invoke-SyncroRequest { param($Configuration, $Endpoint, $Method, $Query, $Body) }
    function Get-NormalizedError { param($Message) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData, $headers) }

    . (Join-Path $BackendRoot 'Modules/CippExtensions/Public/Syncro/Get-SyncroPriority.ps1')
    . (Join-Path $BackendRoot 'Modules/CippExtensions/Public/Syncro/New-SyncroPSATicket.ps1')

    function New-SyncroConfigRow {
        param($DefaultPriority, $ProblemType, $TicketStatus)
        $Syncro = @{ Enabled = $true; Subdomain = 'contoso' }
        if ($PSBoundParameters.ContainsKey('DefaultPriority')) { $Syncro.DefaultPriority = $DefaultPriority }
        if ($PSBoundParameters.ContainsKey('ProblemType')) { $Syncro.ProblemType = $ProblemType }
        if ($PSBoundParameters.ContainsKey('TicketStatus')) { $Syncro.TicketStatus = $TicketStatus }
        [pscustomobject]@{ config = (@{ Syncro = $Syncro } | ConvertTo-Json -Depth 5 -Compress) }
    }

    function Get-SentTicket { $script:SentBody | ConvertFrom-Json }
}

Describe 'New-SyncroPSATicket' {
    BeforeEach {
        $script:SentBody = $null
        $script:SentEndpoint = $null
        Mock Get-CIPPTable { @{ TableName = 'Extensionsconfig' } }
        Mock Get-CIPPAzDataTableEntity { New-SyncroConfigRow -DefaultPriority '2 Normal' }
        Mock Write-LogMessage {}
        Mock Invoke-SyncroRequest {
            $script:SentBody = $Body
            $script:SentEndpoint = $Endpoint
            [pscustomobject]@{ ticket = [pscustomobject]@{ id = 987; number = 2012 } }
        }
    }

    Context 'payload' {
        It 'posts one ticket with the subject, customer and a hidden comment carrying the body' {
            $Result = New-SyncroPSATicket -Title '[CIPP] Alert' -Description '<p>body</p>' -Client '19'

            $script:SentEndpoint | Should -Be '/tickets'
            $Ticket = Get-SentTicket
            $Ticket.customer_id | Should -Be 19
            $Ticket.customer_id | Should -BeOfType [long]
            $Ticket.subject | Should -Be '[CIPP] Alert'
            @($Ticket.comments_attributes).Count | Should -Be 1
            $Ticket.comments_attributes[0].body | Should -Be '<p>body</p>'
            $Ticket.comments_attributes[0].hidden | Should -BeTrue
            $Ticket.comments_attributes[0].do_not_email | Should -BeTrue
            $Result | Should -Be 'Ticket created in Syncro: #2012 (id 987)'
        }

        It 'adds problem type and status only when the integration sets them' {
            $null = New-SyncroPSATicket -Title 'Alert' -Description 'Body' -Client 1
            $Ticket = Get-SentTicket
            $Ticket.PSObject.Properties.Name | Should -Not -Contain 'problem_type'
            $Ticket.PSObject.Properties.Name | Should -Not -Contain 'status'

            Mock Get-CIPPAzDataTableEntity { New-SyncroConfigRow -ProblemType 'Security' -TicketStatus 'New' }
            $null = New-SyncroPSATicket -Title 'Alert' -Description 'Body' -Client 1
            $Ticket = Get-SentTicket
            $Ticket.problem_type | Should -Be 'Security'
            $Ticket.status | Should -Be 'New'
        }

        It 'refuses a customer id that is not a positive integer without calling Syncro' {
            $Result = New-SyncroPSATicket -Title 'Alert' -Description 'Body' -Client 'not-a-customer'

            $Result | Should -BeLike 'Failed to send ticket to Syncro:*not a usable Syncro customer id*'
            Should -Invoke Invoke-SyncroRequest -Times 0 -Exactly
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' }
        }
    }

    Context 'priority' {
        It 'uses the per-alert priority over the integration default' {
            $null = New-SyncroPSATicket -Title 'Alert' -Description 'Body' -Client 1 -TicketPriority '0 Urgent'

            (Get-SentTicket).priority | Should -Be '0 Urgent'
        }

        It 'unwraps the {label, value} shape saved by the alert form' {
            $null = New-SyncroPSATicket -Title 'Alert' -Description 'Body' -Client 1 -TicketPriority @{ label = '1 High'; value = '1 High' }

            (Get-SentTicket).priority | Should -Be '1 High'
        }

        It 'normalises a bare name to the string Syncro expects' {
            $null = New-SyncroPSATicket -Title 'Alert' -Description 'Body' -Client 1 -TicketPriority 'high'

            (Get-SentTicket).priority | Should -Be '1 High'
        }

        It 'falls back to the integration default when no per-alert priority is set' {
            $null = New-SyncroPSATicket -Title 'Alert' -Description 'Body' -Client 1

            (Get-SentTicket).priority | Should -Be '2 Normal'
        }

        It 'skips a HaloPSA priority id and warns rather than guessing a Syncro priority' {
            # Both PSAs enabled: the alert form stored a Halo priority id. '2' must not become '2 Normal'.
            $null = New-SyncroPSATicket -Title 'Alert' -Description 'Body' -Client 1 -TicketPriority '2'

            (Get-SentTicket).priority | Should -Be '2 Normal' -Because 'the integration default is the next source'
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like "*'2' from alert is not a Syncro priority*" }
        }

        It 'sends no priority when neither source holds one so Syncro applies its own default' {
            Mock Get-CIPPAzDataTableEntity { New-SyncroConfigRow }
            $null = New-SyncroPSATicket -Title 'Alert' -Description 'Body' -Client 1

            (Get-SentTicket).PSObject.Properties.Name | Should -Not -Contain 'priority'
            Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $sev -eq 'Warning' }
        }
    }

    Context 'failure' {
        It 'returns the Failed-prefixed line the alert pipeline keys off when Syncro rejects the ticket' {
            Mock Invoke-SyncroRequest { throw 'Unauthorized' }

            $Result = New-SyncroPSATicket -Title 'Alert' -Description 'Body' -Client 1

            $Result | Should -Be 'Failed to send ticket to Syncro: Unauthorized'
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' -and $API -eq 'SyncroTicket' }
        }

        It 'treats a response without a ticket as a failure' {
            Mock Invoke-SyncroRequest { [pscustomobject]@{ error = 'nope' } }

            New-SyncroPSATicket -Title 'Alert' -Description 'Body' -Client 1 | Should -BeLike 'Failed to send ticket to Syncro:*returned no ticket*'
        }
    }
}

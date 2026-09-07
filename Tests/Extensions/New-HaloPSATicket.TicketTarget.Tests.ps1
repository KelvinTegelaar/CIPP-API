# Pester tests for targeting an existing HaloPSA ticket from New-HaloPSATicket.
# A scheduled task raised from a Halo request carries that request's ticket in its reference, so the
# result belongs on that ticket rather than in a second one. The emailed copy already threads onto it
# via the [ID:nnnn] token in the subject; this is the PSA side of the same behaviour. It also sidesteps
# contact matching: an onboarding task creates the user seconds before the ticket is raised, so
# Get-HaloUser can never match and every ticket landed on the client's General User.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CippExtensions/Public/Halo/New-HaloPSATicket.ps1'

    function Get-CIPPTable { param([string]$TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property, $First) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Get-HaloToken { param($configuration) }
    function Get-HaloUser { param($AzureOID, $Email, $ClientId, $Configuration, $Token) }
    function Get-StringHash { param($String) }
    function Get-NormalizedError { param($Message) }
    function Get-CippException { param($Exception) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData, $headers) }

    . $FunctionPath

    function New-HaloConfigRow {
        param([bool]$ConsolidateTickets = $false, [bool]$LinkTicketsToUsers = $true)
        [pscustomobject]@{
            config = (@{
                    HaloPSA = @{
                        Enabled            = $true
                        ResourceURL        = 'https://halo.example.com/api'
                        TicketType         = 21
                        ConsolidateTickets = $ConsolidateTickets
                        LinkTicketsToUsers = $LinkTicketsToUsers
                        Outcome            = @{ label = 'CIPP Update'; value = 155 }
                    }
                } | ConvertTo-Json -Depth 5)
        }
    }

    # Records every call so a test can tell an /actions note from a /Tickets create. The mock body
    # runs in Pester's own scope, not this function's, so the switches have to travel as script-scoped
    # variables rather than closure captures.
    function Set-RestMock {
        param([bool]$TicketExists = $true, [bool]$Closed = $false, [switch]$NoteFails)
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        $script:MockTicketExists = $TicketExists
        $script:MockClosed = $Closed
        $script:MockNoteFails = [bool]$NoteFails
        Mock -CommandName Invoke-RestMethod -MockWith {
            param($Uri, $ContentType, $Method, $Body, $Headers, [switch]$SkipHttpErrorCheck)
            $script:Calls.Add([pscustomobject]@{ Uri = $Uri; Method = $Method; Body = $Body })
            if ($Method -eq 'Get') {
                if (-not $script:MockTicketExists) { return @{} }
                return @{ id = 1380; hasbeenclosed = $script:MockClosed }
            }
            if ($Uri -like '*/actions') {
                if ($script:MockNoteFails) { throw 'Access denied to this action' }
                return @{ id = 5555 }
            }
            @{ id = 1382 }
        }
    }

    function Get-NoteCall { $script:Calls | Where-Object { $_.Uri -like '*/actions' } | Select-Object -First 1 }
    function Get-CreateCall { $script:Calls | Where-Object { $_.Uri -like '*/Tickets' -and $_.Method -eq 'Post' } | Select-Object -First 1 }
}

Describe 'New-HaloPSATicket - targeting a referenced ticket' {
    BeforeEach {
        Mock -CommandName Get-CIPPTable -MockWith { param([string]$TableName) @{ TableName = $TableName } }
        Mock -CommandName Get-HaloToken -MockWith { @{ access_token = 'token' } }
        Mock -CommandName Get-StringHash -MockWith { 'hash' }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-NormalizedError -MockWith { param($Message) $Message }
        Mock -CommandName Get-CippException -MockWith { @{} }
        Mock -CommandName Get-HaloUser -MockWith { $null }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { New-HaloConfigRow }
    }

    Context 'The referenced ticket is open' {
        BeforeEach { Set-RestMock }

        It 'adds a note to that ticket instead of creating one' {
            $Result = New-HaloPSATicket -title 'Test alert' -description '<p>body</p>' -client 19 -TicketId 1380

            $Result | Should -Be 'Note added to ticket in HaloPSA: 1380'
            Get-CreateCall | Should -BeNullOrEmpty
            $Note = @((Get-NoteCall).Body | ConvertFrom-Json)[0]
            $Note.ticket_id | Should -Be 1380
            $Note.note_html | Should -Be '<p>body</p>'
        }

        It 'uses the configured outcome for the note' {
            $null = New-HaloPSATicket -title 'Test alert' -description '<p>body</p>' -client 19 -TicketId 1380

            $Note = @((Get-NoteCall).Body | ConvertFrom-Json)[0]
            $Note.outcome_id | Should -Be 155
        }

        It 'does not try to match a HaloPSA contact for the affected user' {
            # The point of the feature: the ticket already has its user, and a just-created starter
            # would never match anyway.
            $null = New-HaloPSATicket -title 'Test alert' -description '<p>body</p>' -client 19 -TicketId 1380 -UserUPN 'new.starter@contoso.com'

            Should -Invoke Get-HaloUser -Times 0 -Exactly
        }

        It 'ignores the consolidation table when a ticket is named' {
            # Consolidation is keyed on a hash of the title; an explicit ticket must win over it.
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                param($TableName, $Filter)
                if ($Filter) { return [pscustomobject]@{ TicketID = 999 } }
                New-HaloConfigRow -ConsolidateTickets $true
            }

            $null = New-HaloPSATicket -title 'Test alert' -description '<p>body</p>' -client 19 -TicketId 1380

            $Note = @((Get-NoteCall).Body | ConvertFrom-Json)[0]
            $Note.ticket_id | Should -Be 1380
        }
    }

    Context 'The referenced ticket cannot take the note' {
        It 'creates a new ticket and warns when the ticket is closed' {
            Set-RestMock -Closed $true

            $null = New-HaloPSATicket -title 'Test alert' -description '<p>body</p>' -client 19 -TicketId 1380

            Get-NoteCall | Should -BeNullOrEmpty
            Get-CreateCall | Should -Not -BeNullOrEmpty
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like '*1380 is closed*' }
        }

        It 'creates a new ticket and warns when the ticket does not exist' {
            Set-RestMock -TicketExists $false

            $null = New-HaloPSATicket -title 'Test alert' -description '<p>body</p>' -client 19 -TicketId 1380

            Get-CreateCall | Should -Not -BeNullOrEmpty
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like '*could not be found*' }
        }

        It 'creates a new ticket when the note is rejected' {
            Set-RestMock -NoteFails

            $null = New-HaloPSATicket -title 'Test alert' -description '<p>body</p>' -client 19 -TicketId 1380

            Get-CreateCall | Should -Not -BeNullOrEmpty
        }
    }

    Context 'No ticket is referenced' {
        BeforeEach { Set-RestMock }

        It 'creates a ticket exactly as before' {
            $Result = New-HaloPSATicket -title 'Test alert' -description '<p>body</p>' -client 19

            $Result | Should -Be 'Ticket created in HaloPSA: 1382'
            Get-NoteCall | Should -BeNullOrEmpty
        }

        It 'still resolves the affected user' {
            $null = New-HaloPSATicket -title 'Test alert' -description '<p>body</p>' -client 19 -UserUPN 'existing@contoso.com'

            Should -Invoke Get-HaloUser -Times 1 -Exactly
        }
    }
}

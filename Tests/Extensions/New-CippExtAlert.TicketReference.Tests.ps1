# Pester tests for the ticket reference New-CippExtAlert hands to HaloPSA.
# A scheduled task's reference travels with the alert untouched; reading it is this extension's job
# because [ID:nnnn] is HaloPSA's own token - the same one it uses to thread emailed replies onto a
# ticket. When one is present the alert becomes a note on that ticket, and the affected-user lookup
# (plus the Graph call under it) is skipped, since the ticket already carries its end user.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CippExtensions/Public/New-CippExtAlert.ps1'

    function Get-CIPPTable { param([string]$TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property, $First) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function New-HaloPSATicket { param($Title, $Description, $Client, $UserUPN, $AzureOID, $DisplayName, $TicketId) }
    function New-GradientAlert { param($Title, $Description, $Client) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData, $headers) }

    . $FunctionPath

    function New-Alert {
        param($Reference, $AffectedUser, $PsaTicketId)
        $Alert = [pscustomobject]@{
            TenantId   = 'contoso.onmicrosoft.com'
            AlertTitle = '[CIPP] Scheduled Task - contoso - New user creation'
            AlertText  = '<p>body</p>'
        }
        if ($Reference) { $Alert | Add-Member -NotePropertyName Reference -NotePropertyValue $Reference }
        if ($PsaTicketId) { $Alert | Add-Member -NotePropertyName PsaTicketId -NotePropertyValue $PsaTicketId }
        if ($AffectedUser) { $Alert | Add-Member -NotePropertyName AffectedUser -NotePropertyValue $AffectedUser }
        $Alert
    }

    $script:NewStarter = [pscustomobject]@{ UPN = 'new.starter@contoso.com'; DisplayName = 'New Starter' }
}

Describe 'New-CippExtAlert - HaloPSA ticket reference' {
    BeforeEach {
        $script:TicketArgs = $null
        Mock -CommandName Get-CIPPTable -MockWith { param([string]$TableName) @{ TableName = $TableName } }
        Mock -CommandName Get-Tenants -MockWith { [pscustomobject]@{ customerId = 'customer-guid' } }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName New-GraphGetRequest -MockWith { [pscustomobject]@{ id = 'oid-guid'; displayName = 'New Starter' } }
        # An explicit param block is required: a Pester mock body without one leaves
        # $PSBoundParameters empty, which silently passes every "was not passed" assertion.
        Mock -CommandName New-HaloPSATicket -MockWith {
            param($Title, $Description, $Client, $UserUPN, $AzureOID, $DisplayName, $TicketId)
            $script:TicketArgs = [pscustomobject]@{
                Title = $Title; Client = $Client; UserUPN = $UserUPN
                AzureOID = $AzureOID; DisplayName = $DisplayName; TicketId = $TicketId
            }
        }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($TableName, $Filter)
            if ($Filter -like '*HaloMapping*') { return [pscustomobject]@{ RowKey = 'customer-guid'; IntegrationId = 19 } }
            [pscustomobject]@{
                config = (@{ HaloPSA = @{ enabled = $true; LinkTicketsToUsers = $true } } | ConvertTo-Json -Depth 5)
            }
        }
    }

    Context 'The task carries an explicit ticket id' {
        It 'uses PsaTicketId when it is set' {
            # Set from the ticket box on the user / offboarding / scheduler forms.
            New-CippExtAlert -Alert (New-Alert -PsaTicketId 1380)

            $script:TicketArgs.TicketId | Should -Be 1380
        }

        It 'accepts it as a string, which is how the task row stores it' {
            New-CippExtAlert -Alert (New-Alert -PsaTicketId '1380')

            $script:TicketArgs.TicketId | Should -Be 1380
        }

        It 'wins over an [ID:] token in the reference' {
            New-CippExtAlert -Alert (New-Alert -PsaTicketId 1380 -Reference '[ID:99] older reference')

            $script:TicketArgs.TicketId | Should -Be 1380
        }

        It 'warns when the reference names a different ticket' {
            # The reference is what the notification title shows, so a mismatch puts the note on a
            # ticket the title never mentions - which reads as the feature not working at all.
            New-CippExtAlert -Alert (New-Alert -PsaTicketId 1380 -Reference '[ID:1376] Starter Creation')

            $script:TicketArgs.TicketId | Should -Be 1380
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
                $sev -eq 'Warning' -and $message -like '*targets HaloPSA ticket 1380*' -and $message -like '*names ticket 1376*'
            }
        }

        It 'stays quiet when both name the same ticket' {
            New-CippExtAlert -Alert (New-Alert -PsaTicketId 1380 -Reference '[ID:1380] Starter Creation')

            $script:TicketArgs.TicketId | Should -Be 1380
            Should -Invoke Write-LogMessage -Times 0 -Exactly
        }

        It 'skips the contact lookup like any targeted ticket' {
            New-CippExtAlert -Alert (New-Alert -PsaTicketId 1380 -AffectedUser $script:NewStarter)

            Should -Invoke New-GraphGetRequest -Times 0 -Exactly
            $script:TicketArgs.UserUPN | Should -BeNullOrEmpty
        }

        It 'warns and raises a new ticket when the value is not a usable id' {
            New-CippExtAlert -Alert (New-Alert -PsaTicketId 'not-a-ticket')

            $script:TicketArgs.TicketId | Should -BeNullOrEmpty
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like '*not a usable HaloPSA ticket id*' }
        }
    }

    Context 'The reference names a ticket' {
        It 'passes the ticket id through to HaloPSA' {
            New-CippExtAlert -Alert (New-Alert -Reference '[ID:1380] Starter Creation of FirstName LastName')

            $script:TicketArgs.TicketId | Should -Be 1380
        }

        It 'finds the token wherever it sits in the reference' {
            New-CippExtAlert -Alert (New-Alert -Reference 'Starter Creation - see [ID:42] for detail')

            $script:TicketArgs.TicketId | Should -Be 42
        }

        It 'refuses a digit run too large to be a ticket id, and warns' {
            New-CippExtAlert -Alert (New-Alert -Reference '[ID:99999999999999999999]')

            $script:TicketArgs.TicketId | Should -BeNullOrEmpty
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like '*not a usable HaloPSA ticket id*' }
        }

        It 'skips the contact lookup and its Graph call' {
            New-CippExtAlert -Alert (New-Alert -Reference '[ID:1380] Starter' -AffectedUser $script:NewStarter)

            Should -Invoke New-GraphGetRequest -Times 0 -Exactly
            $script:TicketArgs.UserUPN | Should -BeNullOrEmpty
            $script:TicketArgs.AzureOID | Should -BeNullOrEmpty
        }
    }

    Context 'The reference names no ticket' {
        It 'sends no ticket id for a free-text reference' {
            New-CippExtAlert -Alert (New-Alert -Reference 'Starter Creation of FirstName LastName')

            $script:TicketArgs.TicketId | Should -BeNullOrEmpty
        }

        It 'sends no ticket id when there is no reference at all' {
            New-CippExtAlert -Alert (New-Alert)

            $script:TicketArgs.TicketId | Should -BeNullOrEmpty
        }

        It 'still resolves the affected user' {
            New-CippExtAlert -Alert (New-Alert -AffectedUser $script:NewStarter)

            Should -Invoke New-GraphGetRequest -Times 1 -Exactly
            $script:TicketArgs.UserUPN | Should -Be 'new.starter@contoso.com'
            $script:TicketArgs.AzureOID | Should -Be 'oid-guid'
        }

        It 'ignores a reference that merely contains digits' {
            # 'PO 1380' or 'INV-2024-1389' are free text, not a ticket number.
            New-CippExtAlert -Alert (New-Alert -Reference 'PO 1380')

            $script:TicketArgs.TicketId | Should -BeNullOrEmpty
        }

        It 'ignores a reference with digits embedded in an identifier' {
            New-CippExtAlert -Alert (New-Alert -Reference 'INV-2024-1389')

            $script:TicketArgs.TicketId | Should -BeNullOrEmpty
        }

        It 'ignores a bare number - a reference is free text, not a ticket id' {
            # Deliberate: order numbers, asset tags and change ids all live in this field, and
            # treating one as a ticket id would append a starter's password to an unrelated ticket.
            # [ID:nnnn] is required, which is also what Halo's own email threading matches on.
            New-CippExtAlert -Alert (New-Alert -Reference '1389')

            $script:TicketArgs.TicketId | Should -BeNullOrEmpty
        }

        It 'ignores a bare number with surrounding whitespace' {
            New-CippExtAlert -Alert (New-Alert -Reference '  1389  ')

            $script:TicketArgs.TicketId | Should -BeNullOrEmpty
        }
    }
}

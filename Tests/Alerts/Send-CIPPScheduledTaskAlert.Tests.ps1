# Pester tests for Send-CIPPScheduledTaskAlert PSA delivery.
# When HaloPSA's "Link Tickets to affected Users" is on (or a task sets PsaTicketStrategy=split),
# the PSA body is rebuilt from the per-user row group instead of the shared $HTML. Everything
# appended to $HTML after the results table - the snooze buttons and the alert comment - has to
# be re-attached to each split body or the tickets lose it (#165).

BeforeAll {
    Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue

    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPCore/Public/Send-CIPPScheduledTaskAlert.ps1'

    # Stubs for the dependencies we mock. ConvertTo-PSAHtml and Get-AlertContentHash are loaded
    # for real so the test also proves the PSA HTML conversion doesn't strip the snooze markup.
    function Get-CippTable { param([string]$TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property, $First) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPTextReplacement { param($Text, $TenantFilter, [switch]$EscapeForJson) }
    function Send-CIPPAlert {
        param($Type, $Title, $HTMLContent, $JSONContent, $TenantFilter, $altEmail, $altWebhook,
            $APIName, $SchemaSource, $InvokingCommand, $Headers, $TableName, $RowKey,
            $Attachments, $AffectedUser, [switch]$UseStandardizedSchema)
    }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData, $headers) }

    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/ConvertTo-PSAHtml.ps1')
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/GraphHelper/Get-AlertContentHash.ps1')
    . $FunctionPath

    function New-HaloExtConfig {
        param([bool]$LinkTicketsToUsers)
        [pscustomobject]@{
            config = (@{ HaloPSA = @{ Enabled = $true; LinkTicketsToUsers = $LinkTicketsToUsers } } | ConvertTo-Json -Depth 5)
        }
    }
}

Describe 'Send-CIPPScheduledTaskAlert - PSA snooze links' {
    BeforeEach {
        $script:SentAlerts = [System.Collections.Generic.List[object]]::new()
        $script:LinkTicketsToUsers = $true

        $script:Results = @(
            [pscustomobject]@{ UserPrincipalName = 'user1@contoso.com'; DisplayName = 'User One'; MFA = 'Disabled' }
            [pscustomobject]@{ UserPrincipalName = 'user2@contoso.com'; DisplayName = 'User Two'; MFA = 'Disabled' }
        )

        $script:TaskInfo = [pscustomobject]@{
            RowKey            = 'task-1'
            Name              = 'Users without MFA'
            Command           = 'Get-CIPPAlertNoCAConfig'
            PostExecution     = 'psa'
            AlertComment      = 'Please review these accounts.'
            PsaTicketStrategy = ''
            Parameters        = '{}'
        }

        Mock -CommandName Get-CippTable -MockWith { param([string]$TableName) @{ TableName = $TableName } }
        Mock -CommandName Get-Tenants -MockWith { [pscustomobject]@{ customerId = '00000000-0000-0000-0000-000000000001' } }
        Mock -CommandName Get-CIPPTextReplacement -MockWith { param($Text, $TenantFilter) $Text }
        Mock -CommandName Write-LogMessage -MockWith { }

        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($TableName, $Filter)
            switch ($TableName) {
                'Config' { [pscustomobject]@{ Value = 'cipp.contoso.com' } }
                'Extensionsconfig' { New-HaloExtConfig -LinkTicketsToUsers $script:LinkTicketsToUsers }
                default { $null }
            }
        }

        Mock -CommandName Send-CIPPAlert -MockWith {
            param($Type, $Title, $HTMLContent, $JSONContent, $TenantFilter, $AffectedUser, $PSAReference, $PSATicketId)
            $script:SentAlerts.Add([pscustomobject]@{
                    Type         = $Type
                    Title        = $Title
                    HTMLContent  = $HTMLContent
                    AffectedUser = $AffectedUser
                    PSAReference = $PSAReference
                    PSATicketId  = $PSATicketId
                })
        }
    }

    Context 'when tickets are split per affected user' {
        It 'sends one ticket per user' {
            Send-CIPPScheduledTaskAlert -Results $script:Results -TaskInfo $script:TaskInfo -TenantFilter 'contoso.com' -TaskType 'Alert'

            $script:SentAlerts.Count | Should -Be 2
            @($script:SentAlerts.AffectedUser.UPN) | Should -Be @('user1@contoso.com', 'user2@contoso.com')
        }

        It 'keeps the snooze buttons in every split ticket' {
            Send-CIPPScheduledTaskAlert -Results $script:Results -TaskInfo $script:TaskInfo -TenantFilter 'contoso.com' -TaskType 'Alert'

            foreach ($Alert in $script:SentAlerts) {
                $Alert.HTMLContent | Should -Match 'Snooze Individual Alerts'
                foreach ($Duration in 7, 14, 30, 90) {
                    $Alert.HTMLContent | Should -Match "duration=$Duration"
                }
                $Alert.HTMLContent | Should -Match 'https://cipp\.contoso\.com/cipp/snooze-alert'
            }
        }

        It 'scopes each ticket to its own user rows' {
            Send-CIPPScheduledTaskAlert -Results $script:Results -TaskInfo $script:TaskInfo -TenantFilter 'contoso.com' -TaskType 'Alert'

            $First = $script:SentAlerts[0].HTMLContent
            $Second = $script:SentAlerts[1].HTMLContent
            $First | Should -Match 'user1@contoso.com'
            $First | Should -Not -Match 'user2@contoso.com'
            $Second | Should -Match 'user2@contoso.com'
            $Second | Should -Not -Match 'user1@contoso.com'
        }

        It 'keeps the alert comment in every split ticket' {
            Send-CIPPScheduledTaskAlert -Results $script:Results -TaskInfo $script:TaskInfo -TenantFilter 'contoso.com' -TaskType 'Alert'

            foreach ($Alert in $script:SentAlerts) {
                $Alert.HTMLContent | Should -Match 'Please review these accounts\.'
            }
        }

        It 'omits snooze buttons for non-alert task types' {
            Send-CIPPScheduledTaskAlert -Results $script:Results -TaskInfo $script:TaskInfo -TenantFilter 'contoso.com' -TaskType 'Scheduled Task'

            $script:SentAlerts.Count | Should -Be 2
            foreach ($Alert in $script:SentAlerts) {
                $Alert.HTMLContent | Should -Not -Match 'Snooze Individual Alerts'
            }
        }
    }

    Context 'when tickets are consolidated' {
        It 'sends a single ticket carrying every snooze button' {
            $script:LinkTicketsToUsers = $false

            Send-CIPPScheduledTaskAlert -Results $script:Results -TaskInfo $script:TaskInfo -TenantFilter 'contoso.com' -TaskType 'Alert'

            $script:SentAlerts.Count | Should -Be 1
            $script:SentAlerts[0].HTMLContent | Should -Match 'Snooze Individual Alerts'
            $script:SentAlerts[0].HTMLContent | Should -Match 'user1@contoso.com'
            $script:SentAlerts[0].HTMLContent | Should -Match 'user2@contoso.com'
            $script:SentAlerts[0].HTMLContent | Should -Match 'Please review these accounts\.'
        }

        It 'honours a per-task consolidated strategy over the global toggle' {
            $script:TaskInfo.PsaTicketStrategy = 'consolidated'

            Send-CIPPScheduledTaskAlert -Results $script:Results -TaskInfo $script:TaskInfo -TenantFilter 'contoso.com' -TaskType 'Alert'

            $script:SentAlerts.Count | Should -Be 1
            $script:SentAlerts[0].HTMLContent | Should -Match 'Snooze Individual Alerts'
        }
    }

    # The task's reference is what lets a PSA add the result to the ticket the request came from
    # rather than opening a second one, so every PSA call has to carry it - including the per-user
    # split, or a split task's notes would land in new tickets while the consolidated one threads.
    Context 'when the task carries a reference' {
        BeforeEach {
            $script:TaskInfo | Add-Member -NotePropertyName Reference -NotePropertyValue '[ID:1380] Starter Creation' -Force
        }

        It 'passes it on the consolidated ticket' {
            $script:LinkTicketsToUsers = $false

            Send-CIPPScheduledTaskAlert -Results $script:Results -TaskInfo $script:TaskInfo -TenantFilter 'contoso.com' -TaskType 'Alert'

            $script:SentAlerts.Count | Should -Be 1
            $script:SentAlerts[0].PSAReference | Should -Be '[ID:1380] Starter Creation'
        }

        It 'passes it on every split ticket' {
            Send-CIPPScheduledTaskAlert -Results $script:Results -TaskInfo $script:TaskInfo -TenantFilter 'contoso.com' -TaskType 'Alert'

            $script:SentAlerts.Count | Should -Be 2
            foreach ($Alert in $script:SentAlerts) {
                $Alert.PSAReference | Should -Be '[ID:1380] Starter Creation'
            }
        }

        It 'passes an explicit PsaTicketId alongside it' {
            $script:TaskInfo | Add-Member -NotePropertyName PsaTicketId -NotePropertyValue '1380' -Force
            $script:LinkTicketsToUsers = $false

            Send-CIPPScheduledTaskAlert -Results $script:Results -TaskInfo $script:TaskInfo -TenantFilter 'contoso.com' -TaskType 'Alert'

            $script:SentAlerts[0].PSATicketId | Should -Be '1380'
        }

        It 'keeps the ticket id out of the email subject entirely' {
            # PsaTicketId drives the PSA note and nothing else. A mail-ingesting PSA threads on
            # whatever the operator chose to put in Reference, so the subject must not be stamped
            # with a ticket token nobody asked for.
            $script:TaskInfo | Add-Member -NotePropertyName PsaTicketId -NotePropertyValue '1380' -Force
            $script:TaskInfo | Add-Member -NotePropertyName Reference -NotePropertyValue 'Starter Creation' -Force
            $script:TaskInfo.PostExecution = 'email'

            Send-CIPPScheduledTaskAlert -Results $script:Results -TaskInfo $script:TaskInfo -TenantFilter 'contoso.com' -TaskType 'Alert'

            $script:SentAlerts[0].Type | Should -Be 'email'
            $script:SentAlerts[0].Title | Should -Not -Match '\[ID:'
            $script:SentAlerts[0].Title | Should -BeLike '*Reference: Starter Creation*'
        }

        It 'sends nothing extra when the task has no reference' {
            $script:TaskInfo | Add-Member -NotePropertyName Reference -NotePropertyValue $null -Force
            $script:LinkTicketsToUsers = $false

            Send-CIPPScheduledTaskAlert -Results $script:Results -TaskInfo $script:TaskInfo -TenantFilter 'contoso.com' -TaskType 'Alert'

            $script:SentAlerts[0].PSAReference | Should -BeNullOrEmpty
        }
    }
}

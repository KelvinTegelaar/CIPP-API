# Pester tests for how Send-CIPPScheduledTaskAlert renders a result envelope.
# Commands that also serve an HTTP caller return one row carrying the result lines plus the extras
# that caller needs: New-CIPPUserTask hands back Results alongside Username, Password, CopyFrom and
# the whole Graph user object. ConvertTo-Html turns that single row into a column per key, so the
# readable lines ended up squeezed into one cell beside a flattened 78-property Graph object - the
# notification email and the PSA ticket were a single unreadable row.
#
# The split is deliberately a rendering change only: $Results is not modified, so the webhook payload
# and the stored task results keep the shape they have always had, and nothing is dropped from the
# email or ticket either - the extras move below the table instead of beside it.

BeforeAll {
    Add-Type -AssemblyName System.Web -ErrorAction SilentlyContinue

    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPCore/Public/Send-CIPPScheduledTaskAlert.ps1'

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

    # The shape Push-ExecScheduledCommand hands over for a New-CIPPUserTask run: one row, because
    # Select-Object * promotes the returned hashtable's keys to properties.
    function New-EnvelopeResult {
        $Lines = [System.Collections.Generic.List[string]]::new()
        @(
            'Created New User.'
            'Username: starter@contoso.com'
            'Password: https://pwpush.example/p/abc'
            'Successfully added Starter to group Retail'
        ) | ForEach-Object { $Lines.Add($_) }

        , @([pscustomobject]@{
                Results  = $Lines
                Username = 'starter@contoso.com'
                Password = 'https://pwpush.example/p/abc'
                CopyFrom = [pscustomobject]@{ Success = @('group A'); Error = @(); Skipped = @('group B') }
                User     = [pscustomobject]@{
                    id                = '00000000-0000-0000-0000-000000000001'
                    displayName       = 'New Starter'
                    userPrincipalName = 'starter@contoso.com'
                    businessPhones    = @('01603 888888')
                }
            })
    }

    function Get-TableColumns {
        # ConvertTo-PSAHtml rewrites <th> with inline styles on the PSA path, so the header cells
        # cannot be matched as a bare tag.
        param([string]$Html, [int]$TableIndex = 0)
        $Tables = [regex]::Matches($Html, '(?s)<table[^>]*>.*?</table>')
        if ($Tables.Count -le $TableIndex) { return @() }
        @([regex]::Matches($Tables[$TableIndex].Value, '<th[^>]*>(.*?)</th>') | ForEach-Object { $_.Groups[1].Value })
    }
    function Get-TableRowCount {
        param([string]$Html, [int]$TableIndex = 0)
        $Tables = [regex]::Matches($Html, '(?s)<table[^>]*>.*?</table>')
        if ($Tables.Count -le $TableIndex) { return 0 }
        ([regex]::Matches($Tables[$TableIndex].Value, '<tr>')).Count - 1
    }
}

Describe 'Send-CIPPScheduledTaskAlert - result envelope rendering' {
    BeforeEach {
        $script:SentAlerts = [System.Collections.Generic.List[object]]::new()
        $script:TaskInfo = [pscustomobject]@{
            RowKey        = 'task-1'
            Name          = 'New user creation: starter@contoso.com'
            Command       = 'New-CIPPUserTask'
            PostExecution = 'psa'
            Parameters    = '{}'
        }

        Mock -CommandName Get-CippTable -MockWith { param([string]$TableName) @{ TableName = $TableName } }
        Mock -CommandName Get-Tenants -MockWith { [pscustomobject]@{ customerId = 'customer-guid' } }
        Mock -CommandName Get-CIPPTextReplacement -MockWith { param($Text, $TenantFilter) $Text }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($TableName, $Filter)
            if ($TableName -eq 'Extensionsconfig') {
                return [pscustomobject]@{ config = (@{ HaloPSA = @{ Enabled = $false } } | ConvertTo-Json -Depth 5) }
            }
            $null
        }
        Mock -CommandName Send-CIPPAlert -MockWith {
            param($Type, $Title, $HTMLContent)
            $script:SentAlerts.Add([pscustomobject]@{ Type = $Type; HTMLContent = $HTMLContent })
        }
    }

    Context 'a New-CIPPUserTask style envelope' {
        BeforeEach {
            Send-CIPPScheduledTaskAlert -Results (New-EnvelopeResult) -TaskInfo $script:TaskInfo -TenantFilter 'contoso.com' -TaskType 'Scheduled Task'
            $script:Html = $script:SentAlerts[0].HTMLContent
        }

        It 'renders the result lines as the table, one row each' {
            Get-TableColumns -Html $script:Html -TableIndex 0 | Should -Be @('Results')
            Get-TableRowCount -Html $script:Html -TableIndex 0 | Should -Be 4
        }

        It 'keeps the Graph user object rather than dropping it' {
            # The whole point of rendering the extras below instead of unwrapping upstream.
            $script:Html | Should -Match 'Additional detail'
            $script:Html | Should -Match 'displayName: New Starter'
            $script:Html | Should -Match '00000000-0000-0000-0000-000000000001'
        }

        It 'keeps the other envelope fields too' {
            foreach ($Field in 'Username', 'Password', 'CopyFrom', 'User') {
                $script:Html | Should -Match ">$Field<"
            }
        }

        It 'puts the extras in their own table below the results' {
            Get-TableColumns -Html $script:Html -TableIndex 1 | Should -Be @('Field', 'Value')
            $script:Html.IndexOf('Additional detail') | Should -BeGreaterThan $script:Html.IndexOf('Created New User.')
        }
    }

    Context 'result shapes that are not envelopes' {
        It 'renders an array of strings as before' {
            Send-CIPPScheduledTaskAlert -Results @('First line', 'Second line') -TaskInfo $script:TaskInfo -TenantFilter 'contoso.com' -TaskType 'Scheduled Task'

            $Html = $script:SentAlerts[0].HTMLContent
            Get-TableColumns -Html $Html -TableIndex 0 | Should -Be @('Text')
            $Html | Should -Not -Match 'Additional detail'
        }

        It 'renders a normal multi-row result set as before' {
            $Rows = @(
                [pscustomobject]@{ UserPrincipalName = 'a@contoso.com'; MFA = 'Disabled' }
                [pscustomobject]@{ UserPrincipalName = 'b@contoso.com'; MFA = 'Disabled' }
            )
            Send-CIPPScheduledTaskAlert -Results $Rows -TaskInfo $script:TaskInfo -TenantFilter 'contoso.com' -TaskType 'Scheduled Task'

            $Html = $script:SentAlerts[0].HTMLContent
            Get-TableColumns -Html $Html -TableIndex 0 | Should -Be @('UserPrincipalName', 'MFA')
            $Html | Should -Not -Match 'Additional detail'
        }

        It 'leaves a single row that has no Results member alone' {
            $Row = @([pscustomobject]@{ UserPrincipalName = 'a@contoso.com'; MFA = 'Disabled' })
            Send-CIPPScheduledTaskAlert -Results $Row -TaskInfo $script:TaskInfo -TenantFilter 'contoso.com' -TaskType 'Scheduled Task'

            $Html = $script:SentAlerts[0].HTMLContent
            Get-TableColumns -Html $Html -TableIndex 0 | Should -Be @('UserPrincipalName', 'MFA')
            $Html | Should -Not -Match 'Additional detail'
        }
    }
}

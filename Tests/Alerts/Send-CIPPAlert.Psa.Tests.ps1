# Pester tests for the PSA branch of Send-CIPPAlert.
# Two things used to be invisible here: PSA delivery is gated on the "Send to integration"
# notification setting (with it off nothing is sent and nothing was logged), and the PSA extension
# reports failure in its return value rather than by throwing, so a failed ticket was logged as
# "Sent PSA alert" and handed back to the caller as a success.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPCore/Public/Send-CIPPAlert.ps1'

    function Get-CIPPTable { param([string]$TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property, $First) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, $Tenant, [switch]$EscapeForJson) }
    function New-CippExtAlert { param([switch]$TestRun, $Alert) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData, $headers) }
    function Get-CippException { param($Exception) }

    . $FunctionPath

    $script:PsaParams = @{
        Type         = 'psa'
        Title        = 'User Offboarding - contoso.onmicrosoft.com - Offboard AdeleV'
        HTMLContent  = '<p>body</p>'
        TenantFilter = 'contoso.onmicrosoft.com'
    }
}

Describe 'Send-CIPPAlert - PSA delivery' {
    BeforeEach {
        Mock -CommandName Get-CIPPTable -MockWith { param([string]$TableName) @{ TableName = $TableName } }
        Mock -CommandName Get-CIPPTextReplacement -MockWith { param($TenantFilter, $Text, $Tenant, [switch]$EscapeForJson) $Text }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName New-CippExtAlert -MockWith { }
    }

    Context "'Send to integration' is off" {
        BeforeEach {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @{ sendtoIntegration = $false } }
        }

        It 'does not call the PSA extension at all' {
            $null = Send-CIPPAlert @script:PsaParams

            Should -Invoke New-CippExtAlert -Times 0 -Exactly
        }

        It 'returns the skipped marker so the caller can classify it' {
            Send-CIPPAlert @script:PsaParams | Should -Be 'Skipped: PSA delivery is disabled in the notification settings'
        }

        It 'writes a warning naming the setting that has to be turned on' {
            $null = Send-CIPPAlert @script:PsaParams

            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
                $sev -eq 'Warning' -and
                $API -eq 'Webhook Alerts' -and
                $tenant -eq 'contoso.onmicrosoft.com' -and
                $message -like "*PSA delivery skipped for 'User Offboarding - contoso.onmicrosoft.com - Offboard AdeleV'*" -and
                $message -like "*'Send to integration' is off under Settings > Notifications*"
            }
        }
    }

    Context "'Send to integration' is on" {
        BeforeEach {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @{ sendtoIntegration = $true } }
        }

        It 'reports success and keeps the ticket text the extension returned' {
            Mock -CommandName New-CippExtAlert -MockWith { 'Ticket created in HaloPSA: 1380' }

            $Result = Send-CIPPAlert @script:PsaParams

            $Result | Should -BeLike 'Sent PSA alert:*'
            $Result | Should -BeLike '*Ticket created in HaloPSA: 1380*'
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'info' -and $message -like 'Sent PSA alert*' }
        }

        It 'still reports success when the extension returns nothing' {
            $Result = Send-CIPPAlert @script:PsaParams

            $Result | Should -Be 'Sent PSA alert: User Offboarding - contoso.onmicrosoft.com - Offboard AdeleV'
        }

        It 'returns an error when the extension reports a failed ticket' {
            # New-HaloPSATicket returns this string instead of throwing, which is why the caller
            # has to inspect it.
            Mock -CommandName New-CippExtAlert -MockWith { 'Failed to send ticket to HaloPSA: Unauthorized' }

            $Result = Send-CIPPAlert @script:PsaParams

            $Result | Should -Be 'Error: Failed to send ticket to HaloPSA: Unauthorized'
        }

        It 'logs the failed ticket at error severity and never claims it was sent' {
            Mock -CommandName New-CippExtAlert -MockWith { 'Failed to send ticket to HaloPSA: Unauthorized' }

            $null = Send-CIPPAlert @script:PsaParams

            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter {
                $sev -eq 'Error' -and $message -like '*PSA delivery failed for*Failed to send ticket to HaloPSA: Unauthorized*'
            }
            Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $message -like 'Sent PSA alert*' }
        }

        It 'treats an Error-prefixed result as a failure too' {
            Mock -CommandName New-CippExtAlert -MockWith { 'Error: no HaloPSA token could be retrieved' }

            Send-CIPPAlert @script:PsaParams | Should -Be 'Error: Error: no HaloPSA token could be retrieved'
        }
    }
}

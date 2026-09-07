# Pester tests for Get-CIPPAlertMXRecordChanged.
# A domain without a CacheMxRecords row is being observed for the first time; its current
# records establish the baseline and must not be reported as a change.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AlertPath = Join-Path $RepoRoot 'Modules/CIPPAlerts/Public/Alerts/Get-CIPPAlertMXRecordChanged.ps1'

    function Get-CIPPDomainAnalyser { param($TenantFilter) }
    function Get-CippTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Write-AlertTrace { param($cmdletName, $tenantFilter, $data) }
    function Write-LogMessage { param($message, $API, $tenant, $sev) }

    . $AlertPath
}

Describe 'Get-CIPPAlertMXRecordChanged' {
    BeforeEach {
        $script:PreviousResults = @()
        $script:DomainData = @(
            [pscustomobject]@{
                Domain          = 'contoso.com'
                ActualMXRecords = [pscustomobject]@{ Hostname = @('contoso-com.mail.protection.outlook.com') }
                LastRefresh     = '2026-09-04T12:00:00Z'
                MailProvider    = 'Microsoft 365'
            }
        )
        $script:CapturedAlertData = $null

        Mock Get-CIPPDomainAnalyser { $script:DomainData }
        Mock Get-CippTable { @{ TableName = 'CacheMxRecords' } }
        Mock Get-CIPPAzDataTableEntity { $script:PreviousResults }
        Mock Add-CIPPAzDataTableEntity {}
        Mock Write-AlertTrace {
            param($cmdletName, $tenantFilter, $data)
            $script:CapturedAlertData = @($data)
        }
        Mock Write-LogMessage {}
    }

    It 'stores current MX records as the baseline without alerting when no prior domain row exists' {
        Get-CIPPAlertMXRecordChanged -TenantFilter 'tenant.onmicrosoft.com'

        Should -Invoke Write-AlertTrace -Times 0 -Exactly
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Entity.PartitionKey -eq 'tenant.onmicrosoft.com' -and
            $Entity.RowKey -eq 'contoso.com' -and
            $Entity.ActualMXRecords -eq 'contoso-com.mail.protection.outlook.com' -and
            $Force
        }
    }

    It 'alerts when a previously cached domain changes MX records' {
        $script:PreviousResults = @(
            [pscustomobject]@{
                Domain          = 'contoso.com'
                ActualMXRecords = 'old-mx.contoso.com'
            }
        )

        Get-CIPPAlertMXRecordChanged -TenantFilter 'tenant.onmicrosoft.com'

        Should -Invoke Write-AlertTrace -Times 1 -Exactly
        $script:CapturedAlertData.Count | Should -Be 1
        $script:CapturedAlertData[0].Domain | Should -Be 'contoso.com'
        $script:CapturedAlertData[0].PreviousRecords | Should -Be 'old-mx.contoso.com'
        $script:CapturedAlertData[0].CurrentRecords | Should -Be 'contoso-com.mail.protection.outlook.com'
    }

    It 'alerts when an existing cached domain changes from no MX records to populated records' {
        $script:PreviousResults = @(
            [pscustomobject]@{
                Domain          = 'contoso.com'
                ActualMXRecords = ''
            }
        )

        Get-CIPPAlertMXRecordChanged -TenantFilter 'tenant.onmicrosoft.com'

        Should -Invoke Write-AlertTrace -Times 1 -Exactly
        $script:CapturedAlertData.Count | Should -Be 1
        $script:CapturedAlertData[0].PreviousRecords | Should -Be ''
        $script:CapturedAlertData[0].CurrentRecords | Should -Be 'contoso-com.mail.protection.outlook.com'
    }
}

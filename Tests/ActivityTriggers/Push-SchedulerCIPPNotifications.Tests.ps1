BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/Push-SchedulerCIPPNotifications.ps1')

    $script:OriginalTimezone = $env:CIPP_TIMEZONE

    function Get-CIPPTable { param($tablename = 'CippLogs') @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity {
        param($TableName, $Filter)
        if ($TableName -eq 'SchedulerConfig') { return $script:NotificationConfig }
        if ($TableName -eq 'Config') { return [pscustomobject]@{ Value = 'cipp.test' } }
        $Partition = [regex]::Match($Filter, "PartitionKey eq '(\d+)'").Groups[1].Value
        $Severities = @([regex]::Matches($Filter, "Severity eq '(\w+)'").ForEach({ $_.Groups[1].Value }))
        foreach ($Row in $script:Tables[$TableName].Values) {
            if ($Row.PartitionKey -eq $Partition -and ($Filter -notlike '*sentAsAlert eq false*' -or $Row.sentAsAlert -eq $false) -and ($Severities.Count -eq 0 -or $Row.Severity -in $Severities)) {
                [pscustomobject]$Row
            }
        }
    }
    function Add-CIPPAzDataTableEntity {
        param($TableName, $Entity, [switch]$Force)
        foreach ($Item in @($Entity)) {
            $Row = @{}
            foreach ($Property in $Item.PSObject.Properties) { $Row[$Property.Name] = $Property.Value }
            $script:Tables[$TableName]["$($Row.PartitionKey)/$($Row.RowKey)"] = $Row
        }
    }
    function New-CIPPAlertTemplate {
        param($Data, $Format, $InputObject, $CIPPURL)
        $script:Delivered.AddRange([string[]]@($Data.Message))
        @{ htmlcontent = '<p>alert</p>' }
    }
    function Send-CIPPAlert { param($Type, $Title, $HTMLContent, $TenantFilter, $APIName) }
    function Write-LogMessage { param($API, $message, $tenant, $sev, $LogData) }
    function Get-CippException { param($Exception) }

    function Add-LogRow {
        param([DateTimeOffset]$Written, [string]$Message, [string]$Severity = 'Alert', [string]$API = 'Alerts', [bool]$Sent = $false)
        $Zone = if ($env:CIPP_TIMEZONE) { $env:CIPP_TIMEZONE } else { 'UTC' }
        $Partition = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId($Written.UtcDateTime, $Zone).ToString('yyyyMMdd')
        $RowKey = [guid]::NewGuid().ToString()
        $script:Tables.CippLogs["$Partition/$RowKey"] = @{ PartitionKey = $Partition; RowKey = $RowKey; Tenant = 'contoso.test'; API = $API; Message = $Message; Username = 'CIPP'; Severity = $Severity; sentAsAlert = $Sent }
    }
    function Add-StandardsRow {
        param([DateTimeOffset]$Written, [string]$Message, [bool]$Sent = $false)
        $Partition = $Written.LocalDateTime.ToString('yyyyMMdd')
        $RowKey = [guid]::NewGuid().ToString()
        $script:Tables.CippStandardsAlerts["$Partition/$RowKey"] = @{ PartitionKey = $Partition; RowKey = $RowKey; tenant = 'contoso.test'; message = $Message; sentAsAlert = $Sent }
    }
    function Invoke-NotificationRun {
        param([DateTimeOffset]$At)
        $script:Clock = $At.LocalDateTime
        $script:Delivered = [System.Collections.Generic.List[string]]::new()
        Push-SchedulerCIPPNotifications 6>$null
        @($script:Delivered)
    }
}

AfterAll {
    $env:CIPP_TIMEZONE = $script:OriginalTimezone
}

Describe 'Push-SchedulerCIPPNotifications day boundary' {
    BeforeEach {
        $script:Tables = @{ CippLogs = @{}; CippStandardsAlerts = @{} }
        $script:NotificationConfig = [pscustomobject]@{ email = 'ops@contoso.test'; Severity = 'Alert,Warning' }
        Mock Get-Date { $script:Clock }
    }

    It 'sends unsent rows across a date change: <Name>' -ForEach @(
        @{ Name = 'UTC'; Zone = 'UTC'; LogWritten = '2026-11-10T23:50:00Z'; StandardsWritten = '2026-11-10T23:50:00Z'; Run = '2026-11-11T00:05:00Z' }
        @{ Name = 'CIPP zone behind UTC'; Zone = 'America/New_York'; LogWritten = '2026-11-11T00:20:00Z'; StandardsWritten = '2026-11-10T23:50:00Z'; Run = '2026-11-11T01:05:00Z' }
        @{ Name = 'CIPP zone ahead of UTC'; Zone = 'Pacific/Auckland'; LogWritten = '2026-11-10T12:30:00Z'; StandardsWritten = '2026-11-10T12:30:00Z'; Run = '2026-11-10T12:35:00Z' }
    ) {
        $env:CIPP_TIMEZONE = $Zone
        Add-LogRow -Written $LogWritten -Message 'log row'
        Add-StandardsRow -Written $StandardsWritten -Message 'standards row'

        Invoke-NotificationRun -At $Run | Should -Be @('log row', 'standards row')
        Invoke-NotificationRun -At $Run | Should -BeNullOrEmpty
    }

    It 'does not resend rows already sent and keeps ineligible rows out' {
        $env:CIPP_TIMEZONE = 'UTC'
        $Run = [DateTimeOffset]'2026-11-11T00:05:00Z'
        Add-LogRow -Written '2026-11-11T00:01:00Z' -Message 'pending'
        Add-LogRow -Written '2026-11-11T00:02:00Z' -Message 'sent today' -Sent $true
        Add-LogRow -Written '2026-11-10T23:50:00Z' -Message 'sent yesterday' -Sent $true
        Add-LogRow -Written '2026-11-11T00:03:00Z' -Message 'wrong severity' -Severity 'Info'
        Add-LogRow -Written '2026-11-11T00:04:00Z' -Message 'wrong api' -API 'AddUser'
        Add-StandardsRow -Written '2026-11-10T23:50:00Z' -Message 'standards sent yesterday' -Sent $true

        Invoke-NotificationRun -At $Run | Should -Be @('pending')
        Invoke-NotificationRun -At $Run | Should -BeNullOrEmpty
    }
}

function Write-LogMessage {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param(
        $message,
        $tenant = 'None',
        $API = 'None',
        $tenantId = $null,
        $headers,
        $user,
        $sev,
        $LogData = ''
    )
    if ($Headers.'x-ms-client-principal-idp' -eq 'azureStaticWebApps' -or !$Headers.'x-ms-client-principal-idp') {
        $user = $headers.'x-ms-client-principal'
        $username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($user)) | ConvertFrom-Json).userDetails
    } elseif ($Headers.'x-ms-client-principal-idp' -eq 'aad') {
        $Table = Get-CIPPTable -TableName 'ApiClients'
        $Client = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($headers.'x-ms-client-principal-name')'"
        $username = $Client.AppName ?? 'CIPP-API'
        $AppId = $headers.'x-ms-client-principal-name'
    } else {
        try {
            $username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($user)) | ConvertFrom-Json).userDetails
        } catch {
            $username = $user
        }
    }

    if ($headers.'x-forwarded-for') {
        $ForwardedFor = $headers.'x-forwarded-for' -split ',' | Select-Object -First 1
        $IPRegex = '^(?<IP>(?:\d{1,3}(?:\.\d{1,3}){3}|\[[0-9a-fA-F:]+\]|[0-9a-fA-F:]+))(?::\d+)?$'
        $IPAddress = $ForwardedFor -replace $IPRegex, '$1' -replace '[\[\]]', ''
    }

    if ($LogData) { $LogData = ConvertTo-Json -InputObject $LogData -Depth 10 -Compress }

    $Table = Get-CIPPTable -tablename CippLogs

    if (!$tenant) { $tenant = 'None' }
    if (!$username) { $username = 'CIPP' }
    if ($sev -eq 'Debug' -and $env:DebugMode -ne $true) {
        return
    }
    $TzId = if ($env:CIPP_TIMEZONE) { $env:CIPP_TIMEZONE } else { 'UTC' }
    $LocalNow = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, $TzId)
    $PartitionKey = $LocalNow.ToString('yyyyMMdd')
    # Inverted-ticks RowKey: the table service returns rows in ascending RowKey order, so
    # (MaxValue - now) makes a partition read newest-first without scanning it whole. The
    # suffix keeps concurrent writers from colliding; Invoke-ListLogs derives the day
    # partition back out of the tick prefix. Rows written before this scheme have GUID
    # RowKeys and simply sort in arbitrary order within their (historical) partitions.
    $RowKey = '{0:D19}-{1}' -f ([DateTime]::MaxValue.Ticks - [DateTime]::UtcNow.Ticks), [guid]::NewGuid().ToString('N').Substring(0, 12)
    $TableRow = @{
        'Tenant'       = [string]$tenant
        'API'          = [string]$API
        'Message'      = [string]$message
        'Username'     = [string]$username
        'Severity'     = [string]$sev
        'sentAsAlert'  = $false
        'PartitionKey' = [string]$PartitionKey
        'RowKey'       = [string]$RowKey
        'FunctionNode' = [string]$env:WEBSITE_SITE_NAME
        'LogData'      = [string]$LogData
    }
    if ($IPAddress) {
        $TableRow.IP = [string]$IPAddress
    }
    if ($AppId) {
        $TableRow.AppId = [string]$AppId
    }
    if ($tenantId) {
        $TableRow.Add('TenantID', [string]$tenantId)
    }
    $StandardInfo = $script:CippStandardInfoStorage.Value
    if ($StandardInfo) {
        $TableRow.Standard = [string]$StandardInfo.Standard
        $TableRow.StandardTemplateId = [string]$StandardInfo.StandardTemplateId
        if ($StandardInfo.IntuneTemplateId) {
            $TableRow.IntuneTemplateId = [string]$StandardInfo.IntuneTemplateId
        }
        if ($StandardInfo.ConditionalAccessTemplateId) {
            $TableRow.ConditionalAccessTemplateId = [string]$StandardInfo.ConditionalAccessTemplateId
        }
    }
    if ($script:CippScheduledTaskIdStorage.Value) {
        $TableRow.ScheduledTaskId = [string]$script:CippScheduledTaskIdStorage.Value
    }
    if ($script:CippBaselineRunIdStorage.Value) {
        $TableRow.BaselineRunId = [string]$script:CippBaselineRunIdStorage.Value
    }

    $Table.Entity = $TableRow
    Add-CIPPAzDataTableEntity @Table | Out-Null
}

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
    $PartitionKey = (Get-Date -UFormat '%Y%m%d').ToString()
    $TableRow = @{
        'Tenant'       = [string]$tenant
        'API'          = [string]$API
        'Message'      = [string]$message
        'Username'     = [string]$username
        'Severity'     = [string]$sev
        'sentAsAlert'  = $false
        'PartitionKey' = [string]$PartitionKey
        'RowKey'       = [string]([guid]::NewGuid()).ToString()
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
    if ($script:StandardInfo) {
        $TableRow.Standard = [string]$script:StandardInfo.Standard
        $TableRow.StandardTemplateId = [string]$script:StandardInfo.StandardTemplateId
        if ($script:StandardInfo.IntuneTemplateId) {
            $TableRow.IntuneTemplateId = [string]$script:StandardInfo.IntuneTemplateId
        }
        if ($script:StandardInfo.ConditionalAccessTemplateId) {
            $TableRow.ConditionalAccessTemplateId = [string]$script:StandardInfo.ConditionalAccessTemplateId
        }
    }

    $Table.Entity = $TableRow
    Add-CIPPAzDataTableEntity @Table | Out-Null
}

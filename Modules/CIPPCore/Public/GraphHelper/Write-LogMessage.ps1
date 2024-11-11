function Write-LogMessage {
    <#
    .FUNCTIONALITY
    Internal
    #>
    Param(
        $message,
        $tenant = 'None',
        $API = 'None',
        $tenantId = $null,
        $user,
        $sev,
        $LogData = ''
    )
    try {
        $username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($user)) | ConvertFrom-Json).userDetails
    } catch {
        $username = $user
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
        'SentAsAlert'  = $false
        'PartitionKey' = [string]$PartitionKey
        'RowKey'       = [string]([guid]::NewGuid()).ToString()
        'FunctionNode' = [string]$env:WEBSITE_SITE_NAME
        'LogData'      = [string]$LogData
    }


    if ($tenantId) {
        $TableRow.Add('TenantID', [string]$tenantId)
    }

    $Table.Entity = $TableRow
    Add-CIPPAzDataTableEntity @Table | Out-Null
}

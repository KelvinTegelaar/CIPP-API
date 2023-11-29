function Write-LogMessage ($message, $tenant = 'None', $API = 'None', $tenantId = $null, $user, $sev) {
    try {
        $username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($user)) | ConvertFrom-Json).userDetails
    } catch {
        $username = $user
    }

    $Table = Get-CIPPTable -tablename CippLogs

    if (!$tenant) { $tenant = 'None' }
    if (!$username) { $username = 'CIPP' }
    if ($sev -eq 'Debug' -and $env:DebugMode -ne 'true') {
        Write-Information 'Not writing to log file - Debug mode is not enabled.'
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
        'PartitionKey' = $PartitionKey
        'RowKey'       = ([guid]::NewGuid()).ToString()
    }


    if ($tenantId) {
        $TableRow.Add('TenantID', [string]$tenantId)
    }
    
    $Table.Entity = $TableRow
    Add-CIPPAzDataTableEntity @Table | Out-Null
}
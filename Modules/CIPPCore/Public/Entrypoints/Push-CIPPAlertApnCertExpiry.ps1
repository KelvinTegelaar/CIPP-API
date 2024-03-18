function Push-CIPPAlertApnCertExpiry {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        $Item
    )
    $LastRunTable = Get-CIPPTable -Table AlertLastRun

    try {
        $Filter = "RowKey eq 'ApnCertExpiry' and PartitionKey eq '{0}'" -f $Item.tenantid
        $LastRun = Get-CIPPAzDataTableEntity @LastRunTable -Filter $Filter
        $Yesterday = (Get-Date).AddDays(-1)
        if (-not $LastRun.Timestamp.DateTime -or ($LastRun.Timestamp.DateTime -le $Yesterday)) {
            try {
                $Apn = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/applePushNotificationCertificate' -tenantid $Item.tenant
                if ($Apn.expirationDateTime -lt (Get-Date).AddDays(30) -and $Apn.expirationDateTime -gt (Get-Date).AddDays(-7)) {
                    Write-AlertMessage -tenant $($Item.tenant) -message ('Intune: Apple Push Notification certificate for {0} is expiring on {1}' -f $Apn.appleIdentifier, $Apn.expirationDateTime)
                }
            } catch {
                Write-AlertMessage -tenant $($QueueItem.tenant) -message "Failed to check APN certificate expiry for $($QueueItem.tenant): $(Get-NormalizedError -message $_.Exception.message)"
            }
        }
        $LastRun = @{
            RowKey       = 'ApnCertExpiry'
            PartitionKey = $Item.tenantid
        }
        Add-CIPPAzDataTableEntity @LastRunTable -Entity $LastRun -Force
    } catch {
        Write-AlertMessage -tenant $($QueueItem.tenant) -message "Failed to check APN certificate expiry for $($QueueItem.tenant): $(Get-NormalizedError -message $_.Exception.message)"
    }
}

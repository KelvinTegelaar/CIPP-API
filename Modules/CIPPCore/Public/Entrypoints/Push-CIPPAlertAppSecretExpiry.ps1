function Push-CIPPAlertAppSecretExpiry {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        $QueueItem,
        $TriggerMetadata
    )
    $LastRunTable = $QueueItem.LastRunTable


    try {
        $Filter = "RowKey eq 'AppSecretExpiry' and PartitionKey eq '{0}'" -f $QueueItem.tenantid
        $LastRun = Get-CIPPAzDataTableEntity @LastRunTable -Filter $Filter
        $Yesterday = (Get-Date).AddDays(-1)
        if (-not $LastRun.Timestamp.DateTime -or ($LastRun.Timestamp.DateTime -le $Yesterday)) {
            New-GraphGetRequest -uri "https://graph.microsoft.com/beta/applications?`$select=appId,displayName,passwordCredentials" -tenantid $QueueItem.tenant | ForEach-Object {
                foreach ($App in $_) {
                    if ($App.passwordCredentials) {
                        foreach ($Credential in $App.passwordCredentials) {
                            if ($Credential.endDateTime -lt (Get-Date).AddDays(30) -and $Credential.endDateTime -gt (Get-Date).AddDays(-7)) {
                                Write-AlertMessage -tenant $($QueueItem.tenant) -message ("Application '{0}' has secrets expiring on {1}" -f $App.displayName, $Credential.endDateTime)
                            }
                        }
                    }
                }
            }
            $LastRun = @{
                RowKey       = 'AppSecretExpiry'
                PartitionKey = $QueueItem.tenantid
            }
            Add-CIPPAzDataTableEntity @LastRunTable -Entity $LastRun -Force
        }
    } catch {
        # Error handling
    }
}


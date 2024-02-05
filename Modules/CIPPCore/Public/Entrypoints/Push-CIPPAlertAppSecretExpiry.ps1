function Push-CIPPAlertAppSecretExpiry {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        $QueueItem,
        $TriggerMetadata
    )
    $LastRunTable = Get-CIPPTable -Table AlertLastRun

    Write-Host "Checking app expire for $($QueueItem.tenant)"
    try {
        $Filter = "RowKey eq 'AppSecretExpiry' and PartitionKey eq '{0}'" -f $QueueItem.tenantid
        $LastRun = Get-CIPPAzDataTableEntity @LastRunTable -Filter $Filter
        $Yesterday = (Get-Date).AddDays(-1)
        if (-not $LastRun.Timestamp.DateTime -or ($LastRun.Timestamp.DateTime -le $Yesterday)) {
            New-GraphGetRequest -uri "https://graph.microsoft.com/beta/applications?`$select=appId,displayName,passwordCredentials" -tenantid $QueueItem.tenant | ForEach-Object {
                foreach ($App in $_) {
                    Write-Host "checking $($App.displayName)"
                    if ($App.passwordCredentials) {
                        foreach ($Credential in $App.passwordCredentials) {
                            if ($Credential.endDateTime -lt (Get-Date).AddDays(30) -and $Credential.endDateTime -gt (Get-Date).AddDays(-7)) {
                                Write-Host ("Application '{0}' has secrets expiring on {1}" -f $App.displayName, $Credential.endDateTime)
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
        
    }
}


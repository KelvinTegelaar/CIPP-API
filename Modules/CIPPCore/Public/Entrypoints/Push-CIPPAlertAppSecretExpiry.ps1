function Push-CIPPAlertAppSecretExpiry {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        $Item
    )
    $LastRunTable = Get-CIPPTable -Table AlertLastRun
    
    try {
        $Filter = "RowKey eq 'AppSecretExpiry' and PartitionKey eq '{0}'" -f $Item.tenantid
        $LastRun = Get-CIPPAzDataTableEntity @LastRunTable -Filter $Filter
        $Yesterday = (Get-Date).AddDays(-1)
        if (-not $LastRun.Timestamp.DateTime -or ($LastRun.Timestamp.DateTime -le $Yesterday)) {
            Write-Host "Checking app expire for $($Item.tenant)"
            New-GraphGetRequest -uri "https://graph.microsoft.com/beta/applications?`$select=appId,displayName,passwordCredentials" -tenantid $Item.tenant | ForEach-Object {
                foreach ($App in $_) {
                    Write-Host "checking $($App.displayName)"
                    if ($App.passwordCredentials) {
                        foreach ($Credential in $App.passwordCredentials) {
                            if ($Credential.endDateTime -lt (Get-Date).AddDays(30) -and $Credential.endDateTime -gt (Get-Date).AddDays(-7)) {
                                Write-Host ("Application '{0}' has secrets expiring on {1}" -f $App.displayName, $Credential.endDateTime)
                                Write-AlertMessage -tenant $($Item.tenant) -message ("Application '{0}' has secrets expiring on {1}" -f $App.displayName, $Credential.endDateTime)
                            }
                        }
                    }
                }
            }
            $LastRun = @{
                RowKey       = 'AppSecretExpiry'
                PartitionKey = $Item.tenantid
            }
            Add-CIPPAzDataTableEntity @LastRunTable -Entity $LastRun -Force
        }
    } catch {
        Write-AlertMessage -tenant $($QueueItem.tenant) -message "Failed to check App registration expiry for $($QueueItem.tenant): $(Get-NormalizedError -message $_.Exception.message)"
    }
}


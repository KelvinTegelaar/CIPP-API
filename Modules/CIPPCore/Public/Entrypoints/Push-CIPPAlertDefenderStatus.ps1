
function Push-CIPPAlertDefenderStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $QueueItem,
        $TriggerMetadata
    )
    try {
        New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/managedTenants/windowsProtectionStates?`$top=999&`$filter=tenantId eq '$($QueueItem.tenantid)'" | Where-Object { $_.realTimeProtectionEnabled -eq $false -or $_.MalwareprotectionEnabled -eq $false } | ForEach-Object {
            Write-AlertMessage -tenant $($QueueItem.tenant) -message "$($_.managedDeviceName) - Real Time Protection: $($_.realTimeProtectionEnabled) & Malware Protection: $($_.MalwareprotectionEnabled)"
        }
    } catch {
        Write-AlertMessage -tenant $($QueueItem.tenant) -message "Could not get defender status for $($QueueItem.tenant): $(Get-NormalizedError -message $_.Exception.message)"
    }
}

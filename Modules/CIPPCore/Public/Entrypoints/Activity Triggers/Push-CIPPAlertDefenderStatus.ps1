function Push-CIPPAlertDefenderStatus {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Item
    )
    try {
        New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/managedTenants/windowsProtectionStates?`$top=999&`$filter=tenantId eq '$($Item.tenantid)'" | Where-Object { $_.realTimeProtectionEnabled -eq $false -or $_.MalwareprotectionEnabled -eq $false } | ForEach-Object {
            Write-AlertMessage -tenant $($Item.tenant) -message "$($_.managedDeviceName) - Real Time Protection: $($_.realTimeProtectionEnabled) & Malware Protection: $($_.MalwareprotectionEnabled)"
        }
    } catch {
        Write-AlertMessage -tenant $($Item.tenant) -message "Could not get defender status for $($Item.tenant): $(Get-NormalizedError -message $_.Exception.message)"
    }
}

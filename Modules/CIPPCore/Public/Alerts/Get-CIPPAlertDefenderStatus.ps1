function Get-CIPPAlertDefenderStatus {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        $input,
        $TenantFilter
    )
    try {
        New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/managedTenants/windowsProtectionStates?`$top=999&`$filter=tenantId eq '$($TenantFilter)'" | Where-Object { $_.realTimeProtectionEnabled -eq $false -or $_.MalwareprotectionEnabled -eq $false } | ForEach-Object {
            Write-AlertMessage -tenant $($TenantFilter) -message "$($_.managedDeviceName) - Real Time Protection: $($_.realTimeProtectionEnabled) & Malware Protection: $($_.MalwareprotectionEnabled)"
        }
    } catch {
        Write-AlertMessage -tenant $($TenantFilter) -message "Could not get defender status for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}

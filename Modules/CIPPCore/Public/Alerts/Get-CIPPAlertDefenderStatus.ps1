function Get-CIPPAlertDefenderStatus {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )
    try {
        $TenantId = (Get-Tenants | Where-Object -Property defaultDomainName -EQ $TenantFilter).customerId
        $AlertData = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/tenantRelationships/managedTenants/windowsProtectionStates?`$top=999&`$filter=tenantId eq '$($TenantId)'" | Where-Object { $_.realTimeProtectionEnabled -eq $false -or $_.MalwareprotectionEnabled -eq $false } | ForEach-Object {
            "$($_.managedDeviceName) - Real Time Protection: $($_.realTimeProtectionEnabled) & Malware Protection: $($_.MalwareprotectionEnabled)"
        }
        Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData

    } catch {
        Write-AlertMessage -tenant $($TenantFilter) -message "Could not get defender status for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}

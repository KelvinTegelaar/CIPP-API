
function Get-CIPPBitlockerKey {
    [CmdletBinding()]
    param (
        $device,
        $TenantFilter,
        $APIName = 'Get Bitlocker key',
        $ExecutingUser
    )

    try {
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/informationProtection/bitlocker/recoveryKeys?`$filter=deviceId eq '$($device)'" -tenantid $TenantFilter | ForEach-Object {
        (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/informationProtection/bitlocker/recoveryKeys/$($_.id)?`$select=key" -tenantid $TenantFilter).key
        }
        return $GraphRequest
    } catch {
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not add OOO for $($userid)" -Sev 'Error' -tenant $TenantFilter -LogData (Get-CippException -Exception $_)
        return "Could not add out of office message for $($userid). Error: $($_.Exception.Message)"
    }
}



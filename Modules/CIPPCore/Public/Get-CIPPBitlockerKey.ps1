
function Get-CIPPBitlockerKey {
    [CmdletBinding()]
    param (
        $device,
        $TenantFilter,
        $APIName = 'Get BitLocker key',
        $Headers
    )

    try {
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/informationProtection/bitlocker/recoveryKeys?`$filter=deviceId eq '$($device)'" -tenantid $TenantFilter | ForEach-Object {
        (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/informationProtection/bitlocker/recoveryKeys/$($_.id)?`$select=key" -tenantid $TenantFilter).key
        }
        return $GraphRequest
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Could not retrieve BitLocker recovery key for $($device). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Result
    }
}

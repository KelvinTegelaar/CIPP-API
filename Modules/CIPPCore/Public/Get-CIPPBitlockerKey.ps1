
function Get-CIPPBitLockerKey {
    [CmdletBinding()]
    param (
        $Device,
        $TenantFilter,
        $APIName = 'Get BitLocker key',
        $Headers
    )

    try {
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/informationProtection/bitlocker/recoveryKeys?`$filter=deviceId eq '$($Device)'" -tenantid $TenantFilter |
            ForEach-Object {
                $BitLockerKeyObject = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/informationProtection/bitlocker/recoveryKeys/$($_.id)?`$select=key" -tenantid $TenantFilter)
                [PSCustomObject]@{
                    resultText = "Id: $($_.id) Key: $($BitLockerKeyObject.key)"
                    copyField  = $BitLockerKeyObject.key
                    state      = 'success'
                }
            }

        if ($GraphRequest.Count -eq 0) {
            Write-LogMessage -headers $Headers -API $APIName -message "No BitLocker recovery keys found for $($Device)" -Sev Info -tenant $TenantFilter
            return "No BitLocker recovery keys found for $($Device)"
        }
        Write-LogMessage -headers $Headers -API $APIName -message "Retrieved BitLocker recovery keys for $($Device)" -Sev Info -tenant $TenantFilter
        return $GraphRequest
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Could not retrieve BitLocker recovery key for $($Device). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev Error -tenant $TenantFilter -LogData $ErrorMessage
        throw $Result
    }
}

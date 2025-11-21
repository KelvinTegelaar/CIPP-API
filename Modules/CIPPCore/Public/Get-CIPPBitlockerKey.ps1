<#
.SYNOPSIS
    Retrieves BitLocker recovery keys for a managed device from Microsoft Graph API.

.DESCRIPTION
    This function queries the Microsoft Graph API to retrieve all BitLocker recovery keys
    associated with a specified device. It handles cases where no key is found and provides appropriate
    logging and error handling.
.PARAMETER Device
    The ID of the device for which to retrieve BitLocker recovery keys.

.PARAMETER TenantFilter
    The tenant ID to filter the request to the appropriate tenant.

.PARAMETER APIName
    The name of the API operation for logging purposes. Defaults to 'Get BitLocker key'.

.PARAMETER Headers
    The headers to include in the request, typically used for authentication and logging.

.OUTPUTS
    Array of PSCustomObject with properties:
    - resultText: Formatted string containing the key ID and key value
    - copyField: The raw key value
    - state: Status of the operation ('success')

    Or a string message if no keys are found.
#>

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

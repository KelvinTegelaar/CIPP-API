<#
.SYNOPSIS
    Retrieves the FileVault recovery key for a managed device from Microsoft Graph API.

.DESCRIPTION
    This function makes a request to the Microsoft Graph API to retrieve the FileVault recovery key
    for a specified managed device. It handles cases where no key is found and provides appropriate
    logging and error handling.

.PARAMETER Device
    The GUID of the managed device for which to retrieve the FileVault key.

.PARAMETER TenantFilter
    The tenant ID to filter the request to the appropriate tenant.

.PARAMETER APIName
    The name of the API operation for logging purposes. Defaults to 'Get FileVault key'.

.PARAMETER Headers
    The headers to include in the request, typically used for authentication and logging.

.OUTPUTS
    PSCustomObject with properties:
    - resultText: Formatted string containing the key
    - copyField: The raw key value
    - state: Status of the operation ('success')

    Or a string message if no key is found.

#>

function Get-CIPPFileVaultKey {
    [CmdletBinding()]
    param (
        $Device,
        $TenantFilter,
        $APIName = 'Get FileVault key',
        $Headers
    )

    try {
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$Device/getFileVaultKey" -tenantid $TenantFilter

        if ([string]::IsNullOrEmpty($GraphRequest)) {
            $Result = "No FileVault recovery key found for $($Device)"
            Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev Info -tenant $TenantFilter
            return $Result
        }

        Write-LogMessage -headers $Headers -API $APIName -message "Retrieved FileVault recovery key for $($Device)" -Sev Info -tenant $TenantFilter
        return [PSCustomObject]@{
            resultText = "Key: $($GraphRequest)"
            copyField  = $GraphRequest
            state      = 'success'
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Could not retrieve FileVault recovery key for $($Device). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev Error -tenant $TenantFilter -LogData $ErrorMessage
        throw $Result
    }

}

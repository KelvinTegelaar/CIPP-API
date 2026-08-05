<#
.SYNOPSIS
    Retrieves the Intune-managed BIOS password for a managed device from Microsoft Graph API.

.DESCRIPTION
    This function makes a request to the Microsoft Graph API to retrieve the BIOS password Intune
    holds for a specified managed device. Passwords only exist for devices targeted by a BIOS
    configuration profile that manages per-device passwords. It handles cases where no password is
    found and provides appropriate logging and error handling.

.PARAMETER Device
    The GUID of the managed device for which to retrieve the BIOS password. This is the Intune
    managedDevice ID, not the Entra device ID.

.PARAMETER TenantFilter
    The tenant ID to filter the request to the appropriate tenant.

.PARAMETER APIName
    The name of the API operation for logging purposes. Defaults to 'Get BIOS password'.

.PARAMETER Headers
    The headers to include in the request, typically used for authentication and logging.

.OUTPUTS
    PSCustomObject with properties:
    - resultText: Formatted string naming the device serial number
    - copyField: The current BIOS password
    - state: Status of the operation ('success')

    Or a string message if no password is found.

#>

function Get-CIPPBiosPassword {
    [CmdletBinding()]
    param (
        $Device,
        $TenantFilter,
        $APIName = 'Get BIOS password',
        $Headers
    )

    # $Device comes straight off the request body and is interpolated into an OData filter below,
    # so reject anything that is not a GUID before it gets there. A value containing a quote could
    # otherwise close the literal and widen the filter to devices the caller never named.
    $ParsedDeviceId = [guid]::Empty
    if (-not [guid]::TryParse($Device, [ref]$ParsedDeviceId)) {
        $Result = "Invalid device ID for BIOS password retrieval: $($Device)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev Error -tenant $TenantFilter
        throw $Result
    }

    try {
        # Filtered on the collection rather than hardwarePasswordDetails('<id>'), which 404s for a
        # device without a managed BIOS password. The collection returns nothing instead, keeping
        # the common "no password for this device" case out of the error path.
        # Only currentPassword is surfaced, previousPasswords is deliberately not returned.
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/hardwarePasswordDetails?`$filter=id eq '$Device'" -tenantid $TenantFilter | Select-Object -First 1

        if ([string]::IsNullOrEmpty($GraphRequest.currentPassword)) {
            $Result = "No BIOS password found for $($Device)"
            Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev Info -tenant $TenantFilter
            return $Result
        }

        Write-LogMessage -headers $Headers -API $APIName -message "Retrieved BIOS password for $($Device)" -Sev Info -tenant $TenantFilter
        return [PSCustomObject]@{
            resultText = "BIOS password retrieved for serial $($GraphRequest.serialNumber). Copy the password by clicking the copy button"
            copyField  = $GraphRequest.currentPassword
            state      = 'success'
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Could not retrieve BIOS password for $($Device). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev Error -tenant $TenantFilter -LogData $ErrorMessage
        throw $Result
    }

}

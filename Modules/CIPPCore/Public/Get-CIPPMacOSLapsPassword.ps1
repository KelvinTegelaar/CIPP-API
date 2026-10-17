function Get-CIPPMacOSLapsPassword {
    <#
    .SYNOPSIS
        Retrieves the macOS LAPS local administrator password for an Intune managed device.
    .DESCRIPTION
        Reads the password Intune generated for the local admin account created at Apple automated
        device enrollment (ADE). Only devices enrolled through an ADE profile that configures the local
        admin account have one. Graph does not return the account name; it is set in the ADE profile.
    .PARAMETER Device
        The Intune managedDevice ID, not the Entra device ID used by Windows LAPS.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Device,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [string]$APIName = 'Get macOS LAPS Password',

        [Parameter(Mandatory = $false)]
        [object]$Headers
    )

    # $Device comes straight off the request body and is interpolated into the Graph path, so a value
    # with / or .. could otherwise address a different resource than the one device the caller named.
    $ParsedDeviceId = [guid]::Empty
    if (-not [guid]::TryParse($Device, [ref]$ParsedDeviceId)) {
        throw [System.ArgumentException]::new("Invalid managed device ID for macOS LAPS password retrieval: $Device")
    }

    try {
        $GraphRequest = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$($ParsedDeviceId)/retrieveMacOSManagedDeviceLocalAdminAccountDetail" -tenantid $TenantFilter -ErrorAction Stop | Where-Object { $_.adminAccountPassword } | Select-Object -First 1 | ForEach-Object {
            $RotatedDate = $_.passwordLastRotatedDateTime
            [PSCustomObject]@{
                resultText                  = "macOS LAPS password retrieved, last rotated at $RotatedDate. Copy the password by clicking the copy button"
                copyField                   = $_.adminAccountPassword
                passwordLastRotatedDateTime = $RotatedDate
                state                       = 'success'
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Could not retrieve macOS LAPS password for $Device. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw "Could not retrieve macOS LAPS password for $Device. Error: $($ErrorMessage.NormalizedError)"
    }
    if (-not $GraphRequest) {
        Write-LogMessage -headers $Headers -API $APIName -message "No macOS LAPS password found for $Device" -Sev 'Info' -tenant $TenantFilter
        throw [System.Management.Automation.ItemNotFoundException]::new("No macOS LAPS password found for $Device")
    }
    Write-LogMessage -headers $Headers -API $APIName -message "Retrieved macOS LAPS password for $Device" -Sev 'Info' -tenant $TenantFilter
    return $GraphRequest
}

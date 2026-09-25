function Get-CIPPBecRegisteredDevices {
    <#
    .SYNOPSIS
        Collects the Entra devices registered to the investigated user and flags registrations inside the window.
    .DESCRIPTION
        Reads users/{id}/registeredDevices. A device registered during the analysis window is a classic
        persistence move (a VM or BYOD endpoint standing up under the identity, often followed by
        Windows Hello for Business enrolment), so those rows are flagged and sorted first. Intune
        managed devices are collected separately by the Quick scope.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserId
        The user's object id.
    .PARAMETER StartDate
        Window start (UTC).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$UserId,
        [Parameter(Mandatory = $true)][datetime]$StartDate
    )

    $Uri = "https://graph.microsoft.com/v1.0/users/$UserId/registeredDevices/microsoft.graph.device?`$select=id,deviceId,displayName,operatingSystem,operatingSystemVersion,trustType,registrationDateTime,approximateLastSignInDateTime,accountEnabled,isCompliant,isManaged,profileType,enrollmentType,manufacturer,model"
    $Devices = @(New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -AsApp $true)
    $Window = $StartDate.ToUniversalTime()
    $Rows = foreach ($Device in $Devices) {
        if (-not $Device.id) { continue }
        $Registered = if ($Device.registrationDateTime) { ([datetime]$Device.registrationDateTime).ToUniversalTime() } else { $null }
        [pscustomobject]@{
            id                            = $Device.id
            deviceId                      = $Device.deviceId
            displayName                   = $Device.displayName
            operatingSystem               = $Device.operatingSystem
            operatingSystemVersion        = $Device.operatingSystemVersion
            trustType                     = $Device.trustType
            profileType                   = $Device.profileType
            enrollmentType                = $Device.enrollmentType
            manufacturer                  = $Device.manufacturer
            model                         = $Device.model
            accountEnabled                = $Device.accountEnabled
            isCompliant                   = $Device.isCompliant
            isManaged                     = $Device.isManaged
            registrationDateTime          = if ($Registered) { $Registered.ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
            approximateLastSignInDateTime = if ($Device.approximateLastSignInDateTime) { ([datetime]$Device.approximateLastSignInDateTime).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
            RegisteredInWindow            = [bool]($Registered -and $Registered -ge $Window)
        }
    }
    $Data = @($Rows | Sort-Object -Property @{ Expression = { $_.RegisteredInWindow }; Descending = $true }, @{ Expression = { $_.registrationDateTime }; Descending = $true })
    return New-CIPPBecCollectorResult -Data $Data
}

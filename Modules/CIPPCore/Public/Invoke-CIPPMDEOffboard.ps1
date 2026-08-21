function Invoke-CIPPMDEOffboard {
    <#
    .SYNOPSIS
        Offboards a device from Microsoft Defender for Endpoint.
    .DESCRIPTION
        MDE has no portal option to offboard a device, only the API. Resolves the MDE
        machine record(s) for the given Entra device id via the Defender for Endpoint
        machines API, then queues an offboard action for every record that is still
        onboarded. Only supported by the MDE API for Windows client and server devices.
    .PARAMETER AzureADDeviceId
        The Entra device id of the device to offboard. MDE stores this as aadDeviceId
        on the machine record.
    .PARAMETER TenantFilter
        The tenant to run against.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$AzureADDeviceId,
        [Parameter(Mandatory = $true)][string]$TenantFilter
    )

    if ($AzureADDeviceId -eq '00000000-0000-0000-0000-000000000000') {
        throw 'Device has no Entra device id, so it cannot be matched to a Defender for Endpoint machine record.'
    }

    $Scope = 'https://api.securitycenter.microsoft.com/.default'
    $Machines = New-GraphGetRequest -tenantid $TenantFilter -uri "https://api.securitycenter.microsoft.com/api/machines?`$filter=aadDeviceId eq $AzureADDeviceId" -scope $Scope

    $Onboarded = @($Machines | Where-Object { $_.onboardingStatus -eq 'Onboarded' })
    if ($Onboarded.Count -eq 0) {
        if (@($Machines).Count -gt 0) {
            throw "Found $(@($Machines).Count) Defender for Endpoint machine record(s) for this device, but none are currently onboarded."
        }
        throw 'No Defender for Endpoint machine record found for this device.'
    }

    $OffboardBody = @{ Comment = 'Offboarded via CIPP' } | ConvertTo-Json -Compress
    foreach ($Machine in $Onboarded) {
        $null = New-GraphPOSTRequest -uri "https://api.securitycenter.microsoft.com/api/machines/$($Machine.id)/offboard" -tenantid $TenantFilter -body $OffboardBody -scope $Scope
    }

    $Names = @($Onboarded | ForEach-Object { $_.computerDnsName } | Select-Object -Unique) -join ', '
    return "Queued Defender for Endpoint offboarding for $Names ($($Onboarded.Count) machine record(s))"
}

function Invoke-CIPPStandardStaleEntraDevices {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) StaleEntraDevices
    .SYNOPSIS
        (Label) Cleanup stale Entra devices
    .DESCRIPTION
        (Helptext) Cleans up Entra devices that have not connected/signed in for the specified number of days.
        (DocsDescription) Cleans up Entra devices that have not connected/signed in for the specified number of days. First disables and later deletes the devices. More info can be found in the [Microsoft documentation](https://learn.microsoft.com/en-us/entra/identity/devices/manage-stale-devices)
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
            "highimpact"
            "CIS"
        ADDEDCOMPONENT
            {"type":"number","name":"standards.StaleEntraDevices.deviceAgeThreshold","label":"Days before stale(Dont set below 30)"}
        DISABLEDFEATURES

        IMPACT
            High Impact
        POWERSHELLEQUIVALENT
            Remove-MgDevice, Update-MgDevice or Graph API
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/entra-aad-standards#high-impact
    #>

    param($Tenant, $Settings)

    # Get all Entra devices
    $AllDevices = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/devices' -tenantid $Tenant | Where-Object { $null -ne $_.approximateLastSignInDateTime }
    $Date = (Get-Date).AddDays( - [int]$Settings.deviceAgeThreshold)
    $StaleDevices = $AllDevices | Where-Object { $_.approximateLastSignInDateTime -lt $Date }

    If ($Settings.remediate -eq $true) {

        Write-Host 'Remediation not implemented yet'
        # TODO: Implement remediation. For others in the future that want to try this:
        # Good MS guide on what to watch out for https://learn.microsoft.com/en-us/entra/identity/devices/manage-stale-devices#clean-up-stale-devices
        # https://learn.microsoft.com/en-us/graph/api/device-list?view=graph-rest-beta&tabs=http
        # Properties to look at:
        # approximateLastSignInDateTime: For knowing when the device last signed in
        # enrollmentProfileName and operatingSystem: For knowing if it's an AutoPilot device
        # managementType or isManaged: For knowing if it's an Intune managed device. If it is, should be removed from Intune also. Stale intune standard could prossibly be used for this.
        # profileType: For knowing if it's only registered or also managed
        # accountEnabled: For knowing if the device is disabled or not

    }


    if ($Settings.alert -eq $true) {

        if ($StaleDevices.Count -gt 0) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "$($StaleDevices.Count) Stale devices found" -sev Alert
        } else {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'No stale devices found' -sev Info
        }
    }


    if ($Settings.report -eq $true) {

        if ($StaleDevices.Count -gt 0) {
            $StaleReport = ConvertTo-Json -InputObject ($StaleDevices | Select-Object -Property displayName, id, approximateLastSignInDateTime, accountEnabled, enrollmentProfileName, operatingSystem, managementType, profileType) -Depth 10 -Compress
            Add-CIPPBPAField -FieldName 'StaleEntraDevices' -FieldValue $StaleReport -StoreAs json -Tenant $Tenant
        } else {
            Add-CIPPBPAField -FieldName 'StaleEntraDevices' -FieldValue $true -StoreAs bool -Tenant $Tenant
        }
    }
}

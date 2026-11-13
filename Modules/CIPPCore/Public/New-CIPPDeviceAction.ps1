function New-CIPPDeviceAction {
    [CmdletBinding()]
    param(
        $Action,
        $ActionBody = '{}',
        $DeviceFilter,
        $TenantFilter,
        $Headers,
        $APIName
    )
    # The action name becomes part of the Graph path, so only known actions are queued.
    $QueuedActions = @(
        'syncDevice', 'rebootNow', 'locateDevice', 'setDeviceName', 'RotateLocalAdminPassword', 'WindowsDefenderScan',
        'windowsDefenderUpdateSignatures', 'cleanWindowsDevice', 'wipe', 'retire', 'createDeviceLogCollectionRequest',
        'initiateOnDemandProactiveRemediation'
    )
    try {
        if ($Action -eq 'delete') {
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$DeviceFilter" -type DELETE -tenantid $TenantFilter
        } elseif ($Action -eq 'offboardMDEDevice') {
            # DeviceFilter carries the Entra device id here, not the Intune managedDevice id
            $Result = Invoke-CIPPMDEOffboard -AzureADDeviceId $DeviceFilter -TenantFilter $TenantFilter
        } elseif ($Action -eq 'users') {
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$DeviceFilter')/$($Action)/`$ref" -type POST -tenantid $TenantFilter -body $ActionBody
            $regex = "(?<=\(')([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})(?='|\))"
            $PrimaryUser = $ActionBody | Select-String -Pattern $regex -AllMatches | Select-Object -ExpandProperty Matches | Select-Object -ExpandProperty Value
            $Result = "Changed primary user on device $DeviceFilter to $PrimaryUser"
        } elseif ($Action -eq 'removePrimaryUser') {
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$DeviceFilter')/users/`$ref" -type DELETE -tenantid $TenantFilter
            $Result = "Removed primary user from device $DeviceFilter"
        } elseif ($Action -notin $QueuedActions) {
            throw "'$Action' is not a supported device action"
        } else {
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$DeviceFilter')/$($Action)" -type POST -tenantid $TenantFilter -body $ActionBody
            $Result = "Queued $Action on $DeviceFilter"
        }

        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Info
        return $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to queue action $Action on $DeviceFilter : $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -Sev Error -LogData $ErrorMessage
        throw $Result
    }
}

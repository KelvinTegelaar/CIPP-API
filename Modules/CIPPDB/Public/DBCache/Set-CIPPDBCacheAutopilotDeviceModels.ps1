function Set-CIPPDBCacheAutopilotDeviceModels {
    <#
    .SYNOPSIS
        Records every unique Autopilot manufacturer/model pair seen in a tenant into one global table

    .DESCRIPTION
        The strings are stored exactly as Autopilot reports them, because tuple registration
        (manufacturer + model + serial) needs them to match character for character. The table is
        shared across tenants: a pair is written the first time any tenant has it and never again.
        Nothing tenant-identifying (tenant, serial, device id) is stored.

    .PARAMETER TenantFilter
        The tenant to read Autopilot devices from

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        $TestResult = Test-CIPPStandardLicense -StandardName 'AutopilotDeviceModelsCache' -TenantFilter $TenantFilter -Preset Intune -SkipLog
        if ($TestResult -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have Intune license, skipping Autopilot device models cache' -sev Debug
            return
        }

        $Devices = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities?$top=999' -tenantid $TenantFilter
        $Models = @{}
        foreach ($Device in $Devices) {
            if ([string]::IsNullOrWhiteSpace($Device.manufacturer) -or [string]::IsNullOrWhiteSpace($Device.model)) { continue }
            # Keyed on the raw strings: casing or spacing variants of a model are kept as separate rows
            $RowKey = Get-StringHash -String "$($Device.manufacturer)|$($Device.model)"
            $Models[$RowKey] = $Device
        }
        if ($Models.Count -eq 0) { return }

        $Table = Get-CIPPTable -tablename 'AutopilotDeviceModels'
        $Known = [System.Collections.Generic.HashSet[string]]::new([string[]]@((Get-CIPPAzDataTableEntity @Table -Property RowKey).RowKey))
        $FirstSeen = (Get-Date).ToUniversalTime().ToString('o')
        $NewModels = foreach ($RowKey in $Models.Keys) {
            if ($Known.Contains($RowKey)) { continue }
            @{
                PartitionKey = 'AutopilotModel'
                RowKey       = $RowKey
                Manufacturer = [string]$Models[$RowKey].manufacturer
                Model        = [string]$Models[$RowKey].model
                FirstSeen    = $FirstSeen
            }
        }
        if (-not $NewModels) { return }

        # Upsert so two tenants finding the same new model in the same run cannot conflict
        Add-CIPPAzDataTableEntity @Table -Entity @($NewModels) -Force
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Added $(@($NewModels).Count) new Autopilot device models" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Autopilot device models: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
    }
}

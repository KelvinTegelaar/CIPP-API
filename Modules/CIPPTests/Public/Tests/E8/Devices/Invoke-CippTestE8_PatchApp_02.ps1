function Invoke-CippTestE8_PatchApp_02 {
    <#
    .SYNOPSIS
    ACSC Essential Eight (Patch Applications, ML1) - Managed devices have synced with Intune within the last 14 days
    #>
    param($Tenant)

    $TestId = 'E8_PatchApp_02'
    $Name = 'Managed devices have synced with Intune within the last 14 days'

    try {
        $Devices = Get-CIPPTestData -TenantFilter $Tenant -Type 'ManagedDevices'
        if (-not $Devices) {
            Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Skipped' -ResultMarkdown 'No ManagedDevices cached for this tenant.' -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML1 - Patch Applications'
            return
        }

        $Threshold = (Get-Date).AddDays(-14)
        $Stale = foreach ($D in $Devices) {
            $LastSync = $D.lastSyncDateTime
            if (-not $LastSync) { [pscustomobject]@{ Device = $D.deviceName; LastSync = 'never' }; continue }
            $LastSyncDt = [datetime]::Parse($LastSync)
            if ($LastSyncDt -lt $Threshold) { [pscustomobject]@{ Device = $D.deviceName; LastSync = $LastSyncDt.ToString('yyyy-MM-dd') } }
        }

        if (-not $Stale) {
            $Status = 'Passed'
            $Result = "All $($Devices.Count) managed device(s) have synced with Intune within the last 14 days."
        } else {
            $Status = 'Failed'
            $Sb = [System.Text.StringBuilder]::new("$($Stale.Count) of $($Devices.Count) managed device(s) have not synced for >14 days; their patch state is unknown:`n`n| Device | Last sync |`n| :----- | :-------- |`n")
            foreach ($S in ($Stale | Select-Object -First 50)) { $null = $Sb.Append("| $($S.Device) | $($S.LastSync) |`n") }
            $Result = $Sb.ToString()
        }

        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status $Status -ResultMarkdown $Result -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML1 - Patch Applications'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Add-CippTestResult -TenantFilter $Tenant -TestId $TestId -TestType 'Devices' -Status 'Failed' -ResultMarkdown "Test failed: $($ErrorMessage.NormalizedError)" -Risk 'Medium' -Name $Name -UserImpact 'Low' -ImplementationEffort 'Low' -Category 'E8 ML1 - Patch Applications'
    }
}

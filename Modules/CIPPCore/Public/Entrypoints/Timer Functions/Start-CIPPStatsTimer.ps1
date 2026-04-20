function Start-CIPPStatsTimer {
    <#
    .SYNOPSIS
    Start the CIPP Stats Timer
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()
    #These stats are sent to a central server to help us understand how many tenants are using the product, and how many are using the latest version, this information allows the CIPP team to make decisions about what features to support, and what features to deprecate.


    if ($PSCmdlet.ShouldProcess('Start-CIPPStatsTimer', 'Starting CIPP Stats Timer')) {
        if ($env:ApplicationID -ne 'LongApplicationID') {
            $SetupComplete = $true
        }
        $TenantCount = (Get-Tenants -IncludeAll).count


        $APIVersion = Get-Content (Join-Path $env:CIPPRootPath 'version_latest.txt') | Out-String
        $Table = Get-CIPPTable -TableName Extensionsconfig
        try {
            $RawExt = (Get-CIPPAzDataTableEntity @Table).config | ConvertFrom-Json -Depth 10 -ErrorAction Stop
        } catch {
            $RawExt = @{}
        }

        # Get counts of various entities across all tenants
        $counts = Get-CIPPDbItem -TenantFilter AllTenants -CountsOnly
        $userCount = ($counts | Where-Object { $_.RowKey -eq 'Users-Count' } | Measure-Object -Property DataCount -Sum).Sum
        $deviceCount = ($counts | Where-Object { $_.RowKey -eq 'Devices-Count' } | Measure-Object -Property DataCount -Sum).Sum
        $groupsCount = ($counts | Where-Object { $_.RowKey -eq 'Groups-Count' } | Measure-Object -Property DataCount -Sum).Sum
        $managedDevicesCount = ($counts | Where-Object { $_.RowKey -eq 'ManagedDevices-Count' } | Measure-Object -Property DataCount -Sum).Sum
        $policyCount = ($counts | Where-Object { $_.RowKey -match 'Intune' -and $_.RowKey -match 'Policies|Policy' } | Measure-Object -Property DataCount -Sum).Sum

        $SendingObject = [PSCustomObject]@{
            rgid                = $env:WEBSITE_SITE_NAME
            SetupComplete       = $SetupComplete
            RunningVersionAPI   = $APIVersion.trim()
            CountOfTotalTenants = $TenantCount
            uid                 = $env:TenantID
            UserCount           = $userCount
            DeviceCount         = $deviceCount
            GroupsCount         = $groupsCount
            ManagedDevicesCount = $managedDevicesCount
            PolicyCount         = $policyCount
            CIPPAPI             = $RawExt.CIPPAPI.Enabled
            Hudu                = $RawExt.Hudu.Enabled
            Sherweb             = $RawExt.Sherweb.Enabled
            Gradient            = $RawExt.Gradient.Enabled
            NinjaOne            = $RawExt.NinjaOne.Enabled
            haloPSA             = $RawExt.haloPSA.Enabled
            HIBP                = $RawExt.HIBP.Enabled
            PWPush              = $RawExt.PWPush.Enabled
            CFZTNA              = $RawExt.CFZTNA.Enabled
            GitHub              = $RawExt.GitHub.Enabled
        } | ConvertTo-Json
        try {
            Invoke-CIPPRestMethod -Uri 'https://management.cipp.app/api/stats' -Method POST -Body $SendingObject -ContentType 'application/json'
        } catch {
            $rand = Get-Random -Minimum 0.5 -Maximum 5.5
            Start-Sleep -Seconds $rand
            Invoke-CIPPRestMethod -Uri 'https://management.cipp.app/api/stats' -Method POST -Body $SendingObject -ContentType 'application/json'
        }
    }
}

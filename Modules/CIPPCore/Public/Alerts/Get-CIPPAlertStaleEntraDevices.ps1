function Get-CIPPAlertStaleEntraDevices {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )

    try {
        try {
            $inactiveDays = 90

            $excludeDisabled = [bool]$InputValue.ExcludeDisabled
            if ($null -ne $InputValue.DaysSinceLastActivity -and $InputValue.DaysSinceLastActivity -ne '') {
                $parsedDays = 0
                if ([int]::TryParse($InputValue.DaysSinceLastActivity.ToString(), [ref]$parsedDays) -and $parsedDays -gt 0) {
                    $inactiveDays = $parsedDays
                }
            }

            $Lookup = (Get-Date).AddDays(-$inactiveDays).ToUniversalTime()
            Write-Host "Checking for inactive Entra devices since $Lookup (excluding disabled: $excludeDisabled)"
            # Build base filter - cannot filter accountEnabled server-side
            $BaseFilter = if ($excludeDisabled) { 'accountEnabled eq true' } else { '' }

            $Uri = if ($BaseFilter) {
                "https://graph.microsoft.com/beta/devices?`$filter=$BaseFilter"
            } else {
                'https://graph.microsoft.com/beta/devices'
            }

            $GraphRequest = New-GraphGetRequest -uri $Uri -tenantid $TenantFilter

            $AlertData = foreach ($device in $GraphRequest) {

                $lastActivity = $device.approximateLastSignInDateTime

                $isInactive = (-not $lastActivity) -or ([DateTime]$lastActivity -le $Lookup)
                # Only process stale Entra devices
                if ($isInactive) {

                    if (-not $lastActivity) {

                        $Message = 'Device {0} has never been active' -f $device.displayName
                    } else {
                        $daysSinceLastActivity = [Math]::Round(((Get-Date) - [DateTime]$lastActivity).TotalDays)
                        $Message = 'Device {0} has been inactive for {1} days. Last activity: {2}' -f $device.displayName, $daysSinceLastActivity, $lastActivity
                    }

                    if ($device.TrustType -eq 'Workplace') { $TrustType = 'Entra registered' }
                    elseif ($device.TrustType -eq 'AzureAd') { $TrustType = 'Entra joined' }
                    elseif ($device.TrustType -eq 'ServerAd') { $TrustType = 'Entra hybrid joined' }

                    [PSCustomObject]@{
                        DeviceName            = if ($device.displayName) { $device.displayName } else { 'N/A' }
                        Id                    = if ($device.id) { $device.id } else { 'N/A' }
                        deviceOwnership       = if ($device.deviceOwnership) { $device.deviceOwnership } else { 'N/A' }
                        operatingSystem       = if ($device.operatingSystem) { $device.operatingSystem } else { 'N/A' }
                        enrollmentType        = if ($device.enrollmentType) { $device.enrollmentType } else { 'N/A' }
                        Enabled               = if ($device.accountEnabled) { $device.accountEnabled } else { 'N/A' }
                        Managed               = if ($device.isManaged) { $device.isManaged } else { 'N/A' }
                        Complaint             = if ($device.isCompliant) { $device.isCompliant } else { 'N/A' }
                        JoinType              = $TrustType
                        lastActivity          = if ($lastActivity) { $lastActivity } else { 'N/A' }
                        DaysSinceLastActivity = if ($daysSinceLastActivity) { $daysSinceLastActivity } else { 'N/A' }
                        RegisteredDateTime    = if ($device.createdDateTime) { $device.createdDateTime } else { 'N/A' }
                        Message               = $Message
                        Tenant                = $TenantFilter
                    }
                }
            }

            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        } catch {}
    } catch {
        Write-LogMessage -API 'Alerts' -tenant $($TenantFilter) -message "Failed to check inactive guest users for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)" -sev Error
    }
}

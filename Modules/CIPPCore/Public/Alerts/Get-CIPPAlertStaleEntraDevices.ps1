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

            if ($InputValue -is [hashtable] -or $InputValue -is [pscustomobject]) {
                $excludeDisabled = [bool]$InputValue.ExcludeDisabled
                if ($null -ne $InputValue.DaysSinceLastActivity -and $InputValue.DaysSinceLastActivity -ne '') {
                    $parsedDays = 0
                    if ([int]::TryParse($InputValue.DaysSinceLastActivity.ToString(), [ref]$parsedDays) -and $parsedDays -gt 0) {
                        $inactiveDays = $parsedDays
                    }
                }
            }
            elseif ($InputValue -eq $true) {
                # Backwards compatibility: legacy single-input boolean means exclude disabled users
                $excludeDisabled = $true
            }

            $Lookup = (Get-Date).AddDays(-$inactiveDays).ToUniversalTime()
            Write-Host "Checking for inactive Entra devices since $Lookup (excluding disabled: $excludeDisabled)"
            # Build base filter - cannot filter accountEnabled server-side
            $BaseFilter = if ($excludeDisabled) { 'accountEnabled eq true' } else { '' }

            $Uri = if ($BaseFilter) {
                "https://graph.microsoft.com/beta/devices?`$filter=$BaseFilter"
            }
            else {
                "https://graph.microsoft.com/beta/devices"
            }

            $GraphRequest = New-GraphGetRequest -uri $Uri -scope 'https://graph.microsoft.com/.default' -tenantid $TenantFilter

            $AlertData = foreach ($device in $GraphRequest) {

                $lastActivity = $device.approximateLastSignInDateTime

                # Check if inactive
                $isInactive = (-not $lastActivity) -or ([DateTime]$lastActivity -le $Lookup)
                # Only process stale Entra devices
                if ($isInactive) {

                    $daysSinceLastActivity = [Math]::Round(((Get-Date) - [DateTime]$lastActivity).TotalDays)
                    $Message = 'Device {0} has been inactive for {1} days. Last activity: {2}' -f $device.displayName, $daysSinceLastActivity, $lastActivity

                    if ($device.TrustType -eq "Workplace") { $TrustType = "Entra registered" }
                    elseif ($device.TrustType -eq "AzureAd") { $TrustType = "Entra joined" }
                    elseif ($device.TrustType -eq "ServerAd") { $TrustType = "Entra hybrid joined" }


                    [PSCustomObject]@{
                        DeviceName         = $device.displayName
                        Id                 = $device.id
                        deviceOwnership    = $device.deviceOwnership
                        operatingSystem    = $device.operatingSystem
                        enrollmentType     = $device.enrollmentType
                        Enabled            = $device.accountEnabled
                        Managed            = $device.isManaged
                        JoinType           = $TrustType
                        lastActivity       = $lastActivity
                        RegisteredDateTime = $device.registeredDateTime
                        Message            = $Message
                        Tenant             = $TenantFilter
                    }
                }
            }

            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
        catch {}
    }
    catch {
        Write-AlertMessage -tenant $($TenantFilter) -message "Failed to check inactive guest users for $($TenantFilter): $(Get-NormalizedError -message $_.Exception.message)"
    }
}

function Get-CIPPAlertDeviceComplianceGracePeriod {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter
    )
    try {
        $ExpiresWithinDays = 0
        if ($null -ne $InputValue.ExpiresWithinDays -and $InputValue.ExpiresWithinDays -ne '') {
            $parsedDays = 0
            if ([int]::TryParse($InputValue.ExpiresWithinDays.ToString(), [ref]$parsedDays) -and $parsedDays -gt 0) {
                $ExpiresWithinDays = $parsedDays
            }
        }

        $GraphRequest = New-GraphGETRequest -uri "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$filter=complianceState eq 'inGracePeriod'&`$select=id,deviceName,userPrincipalName,operatingSystem,managedDeviceOwnerType,complianceState,complianceGracePeriodExpirationDateTime,lastSyncDateTime&`$top=999" -tenantid $TenantFilter
        $AlertData = foreach ($Device in $GraphRequest) {
            $Expiration = $Device.complianceGracePeriodExpirationDateTime
            $DaysRemaining = if ($Expiration) { [Math]::Ceiling(([DateTime]$Expiration - (Get-Date).ToUniversalTime()).TotalDays) } else { $null }
            if ($ExpiresWithinDays -gt 0 -and $null -ne $DaysRemaining -and $DaysRemaining -gt $ExpiresWithinDays) { continue }

            $Message = if ($null -ne $DaysRemaining) {
                'Device {0} is in the compliance grace period and will be marked noncompliant on {1} ({2} days remaining)' -f $Device.deviceName, ([datetime]$Expiration).ToString('yyyy-MM-dd'), $DaysRemaining
            } else {
                'Device {0} is in the compliance grace period' -f $Device.deviceName
            }

            [PSCustomObject]@{
                DeviceName            = $Device.deviceName
                Id                    = $Device.id
                UserPrincipalName     = $Device.userPrincipalName
                OperatingSystem       = $Device.operatingSystem
                OwnerType             = $Device.managedDeviceOwnerType
                GracePeriodExpiration = $Expiration
                DaysRemaining         = $DaysRemaining
                LastSync              = $Device.lastSyncDateTime
                Message               = $Message
                Tenant                = $TenantFilter
            }
        }

        if ($AlertData) {
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Alerts' -tenant $TenantFilter -message "Could not get compliance grace period state for $($TenantFilter): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}

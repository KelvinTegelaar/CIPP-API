function Set-CIPPGroupGAL(
    [string]$Headers,
    [string]$GroupType,
    [string]$Id,
    [string]$HiddenString,
    [string]$TenantFilter,
    [string]$APIName = 'Group GAL Status'
) {
    $Hidden = if ($HiddenString -eq 'true') { 'true' } else { 'false' }
    $messageSuffix = if ($Hidden -eq 'true') { 'hidden' } else { 'unhidden' }

    try {
        if ($GroupType -eq 'Distribution List' -or $GroupType -eq 'Mail-Enabled Security') {
            New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-DistributionGroup' -cmdParams @{Identity = $Id; HiddenFromAddressListsEnabled = $Hidden }
        } elseif ($GroupType -eq 'Microsoft 365') {
            New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-UnifiedGroup' -cmdParams @{Identity = $Id; HiddenFromAddressListsEnabled = $Hidden }
        } elseif ($GroupType -eq 'Security') {
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message 'This setting cannot be set on a security group.' -Sev 'Error'
            return "$GroupType's group cannot have this setting changed"
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "$Id $messageSuffix from GAL failed: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return "Failed. $($ErrorMessage.NormalizedError)"
    }

    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "$Id $messageSuffix from GAL" -Sev 'Info'
    return "Successfully $messageSuffix $GroupType group $Id from GAL."
}

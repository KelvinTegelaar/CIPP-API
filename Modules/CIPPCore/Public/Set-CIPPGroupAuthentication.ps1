function Set-CIPPGroupAuthentication(
    [string]$ExecutingUser,
    [string]$GroupType,
    [string]$Id,
    [string]$OnlyAllowInternalString,
    [string]$TenantFilter,
    [string]$APIName = 'Group Sender Authentication'
) {
    try {
        $OnlyAllowInternal = if ($OnlyAllowInternalString -eq 'true') { 'true' } else { 'false' }
        $messageSuffix = if ($OnlyAllowInternal -eq 'true') { 'inside the organisation.' } else { 'inside and outside the organisation.' }

        if ($GroupType -eq 'Distribution List' -or $GroupType -eq 'Mail-Enabled Security') {
            New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-DistributionGroup' -cmdParams @{Identity = $Id; RequireSenderAuthenticationEnabled = $OnlyAllowInternal }
        } elseif ($GroupType -eq 'Microsoft 365') {
            New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-UnifiedGroup' -cmdParams @{Identity = $Id; RequireSenderAuthenticationEnabled = $OnlyAllowInternal }
        } elseif ($GroupType -eq 'Security') {
            Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message 'This setting cannot be set on a security group.' -Sev 'Error'
            return "$GroupType's group cannot have this setting changed"
        }

        Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "$Id set to allow messages from people $messageSuffix" -Sev 'Info'
        return "Set $GroupType group $Id to allow messages from people $messageSuffix"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "Delivery Management failed: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return "Failed. $($ErrorMessage.NormalizedError)"
    }
}

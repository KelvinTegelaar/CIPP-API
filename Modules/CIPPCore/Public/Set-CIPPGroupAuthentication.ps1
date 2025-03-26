function Set-CIPPGroupAuthentication(
    [string]$Headers,
    [string]$GroupType,
    [string]$Id,
    [bool]$OnlyAllowInternal,
    [string]$TenantFilter,
    [string]$APIName = 'Group Sender Authentication'
) {
    try {
        $messageSuffix = if ($OnlyAllowInternal -eq $true) { 'inside the organisation.' } else { 'inside and outside the organisation.' }

        if ($GroupType -eq 'Distribution List' -or $GroupType -eq 'Mail-Enabled Security') {
            New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-DistributionGroup' -cmdParams @{Identity = $Id; RequireSenderAuthenticationEnabled = $OnlyAllowInternal }
        } elseif ($GroupType -eq 'Microsoft 365') {
            New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-UnifiedGroup' -cmdParams @{Identity = $Id; RequireSenderAuthenticationEnabled = $OnlyAllowInternal }
        } elseif ($GroupType -eq 'Security') {
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message 'This setting cannot be set on a security group.' -Sev 'Error'
            return "$GroupType's group cannot have this setting changed"
        }

        $Message = "Successfully set $GroupType group $Id to allow messages from people $messageSuffix"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
        return $Message
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to set Delivery Management: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
        return $Message
    }
}

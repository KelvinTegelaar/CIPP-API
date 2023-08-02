function Set-CIPPGroupGAL(
    [string]$ExecutingUser,
    [string]$GroupType, 
    [string]$Id, 
    [string]$HiddenString, 
    [string]$TenantFilter,
    [string]$APIName = "Group GAL Status"
) {
    $Hidden = if ($HiddenString -eq 'true') { "true" } else { "false" }
    $messageSuffix = if ($Hidden -eq 'true') { "hidden" } else { "unhidden" }

    if ($GroupType -eq "Distribution List" -or $GroupType -eq "Mail-Enabled Security") {
        New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-DistributionGroup" -cmdParams @{Identity = $Id; HiddenFromAddressListsEnabled = $Hidden }
    } 
    elseif ($GroupType -eq "Microsoft 365") {
        New-ExoRequest -tenantid $TenantFilter -cmdlet "Set-UnifiedGroup" -cmdParams @{Identity = $Id; HiddenFromAddressListsEnabled = $Hidden }
    } 
    elseif ($GroupType -eq "Security") {
        Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "This setting cannot be set on a security group." -Sev "Error"
        return "$GroupType's group cannot have this setting changed"
    }
    
    Write-LogMessage -user $ExecutingUser -API $APIName -tenant $TenantFilter -message "$Id $messageSuffix from GAL" -Sev "Info"
    return "Successfully $messageSuffix $GroupType group $Id from GAL."
}

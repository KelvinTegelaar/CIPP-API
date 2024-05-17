function Set-CIPPProfilePhoto {
    [CmdletBinding()]
    param(
        $TenantFilter,
        $id,
        [ValidateSet('users', 'groups', 'teams')]
        $type = 'users',
        $ContentType = 'image/png',
        $PhotoBase64,
        $executingUser
    )
    try {
        $PhotoBytes = [Convert]::FromBase64String($PhotoBase64)
        New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$type/$id/photo/`$value" -tenantid $tenantfilter -type PUT -body $PhotoBytes -ContentType $ContentType
        "Successfully set profile photo for $id"
        Write-LogMessage -user $executingUser -API 'Set-CIPPUserProfilePhoto' -message "Successfully set profile photo for $id" -Sev 'Info' -tenant $TenantFilter
    } catch {
        "Failed to set profile photo for $id : $_"
        Write-LogMessage -user $executingUser -API 'Set-CIPPUserProfilePhoto' -message "Failed to set profile photo for $id : $_" -Sev 'Error' -tenant $TenantFilter
    }
}
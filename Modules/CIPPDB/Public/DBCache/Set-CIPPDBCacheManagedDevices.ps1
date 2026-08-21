function Set-CIPPDBCacheManagedDevices {
    <#
    .SYNOPSIS
        Caches all Intune managed devices for a tenant

    .PARAMETER TenantFilter
        The tenant to cache managed devices for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching managed devices' -sev Debug
        New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/managedDevices?$top=999' -tenantid $TenantFilter -Stream |
            ForEach-Object {
                # Windows 365 Cloud PCs never report BitLocker (isEncrypted stays false) although
                # their disks are platform-encrypted by Azure; the marker is stamped on every row
                # so it is always available as a report column, not only when the first cached
                # device happens to be a Cloud PC.
                $_ | Add-Member -NotePropertyName 'isCloudPC' -NotePropertyValue ([bool](Test-CIPPCloudPCDevice -Device $_)) -Force
                $_
            } |
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ManagedDevices' -AddCount
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached managed devices successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache managed devices: $($_.Exception.Message)" -sev Error
    }
}

function Set-CIPPDBCacheManagedDeviceEncryptionStates {
    <#
    .SYNOPSIS
        Caches encryption states (BitLocker/FileVault) for managed devices in a tenant

    .PARAMETER TenantFilter
        The tenant to cache managed device encryption states for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching managed device encryption states' -sev Debug

        # A row per device, iterated once, so it is streamed into the writer instead of held whole.
        # The writer is opened on the first record: an empty result previously skipped
        # Add-CIPPDbItem altogether, and piping into it unconditionally would run its end block
        # and overwrite the count row with 0.
        # Language foreach (not ForEach-Object) so Begin/Process/End share function scope with the
        # steppable pipeline. Do not wrap New-GraphGetRequest in (...): that buffers the stream.
        $Writer = $null
        $CachedCount = 0
        try {
            foreach ($Item in New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/managedDeviceEncryptionStates?$top=999' -tenantid $TenantFilter -Stream) {
                if ($null -eq $Writer) {
                    $Writer = { Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ManagedDeviceEncryptionStates' -AddCount }.GetSteppablePipeline()
                    $Writer.Begin($true)
                }
                $CachedCount++
                $Writer.Process($Item)
            }
            if ($Writer) {
                $Writer.End()
                $Writer.Dispose()
                $Writer = $null
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $CachedCount managed device encryption states" -sev Debug
            }
        } finally {
            # Only set if the stream threw part-way: dispose without End so a partial run never
            # triggers the writer's orphan cleanup.
            if ($Writer) { $Writer.Dispose() }
        }

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache managed device encryption states: $($_.Exception.Message)" -sev Error
    }
}

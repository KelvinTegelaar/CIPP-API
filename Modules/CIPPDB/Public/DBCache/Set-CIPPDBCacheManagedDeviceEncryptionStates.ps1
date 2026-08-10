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
        # The writer is opened before the pipeline on purpose: GetSteppablePipeline() captures
        # whichever scope is live, so opening it inside ForEach-Object captures the Graph call's
        # scope, which is gone by End() - the end block then fails with "is not recognized".
        # A language 'foreach' avoids that too, but buffers the whole result first.
        $CachedCount = 0
        $Writer = { Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ManagedDeviceEncryptionStates' -AddCount }.GetSteppablePipeline()
        $Writer.Begin($true)
        try {
            New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/managedDeviceEncryptionStates?$top=999' -tenantid $TenantFilter -Stream | ForEach-Object {
                $CachedCount++
                $Writer.Process($_)
            }
            # An empty result must not run the end block (it would zero the count row), nor must
            # a part-way failure (its orphan cleanup). Dispose() alone does not run it.
            if ($CachedCount -gt 0) {
                $Writer.End()
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $CachedCount managed device encryption states" -sev Debug
            }
        } finally {
            $Writer.Dispose()
        }

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache managed device encryption states: $($_.Exception.Message)" -sev Error
    }
}

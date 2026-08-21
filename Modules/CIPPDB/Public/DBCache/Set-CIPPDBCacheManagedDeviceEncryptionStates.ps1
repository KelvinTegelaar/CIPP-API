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

        # Encryption-state rows carry no model/manufacturer and their deviceType enum predates
        # cloudPC, so a row cannot identify a Windows 365 Cloud PC by itself. The ManagedDevices
        # cache (written earlier in the same Intune collection) can: rows share the managed
        # device id. Cloud PCs are platform-encrypted by Azure but never report BitLocker, so
        # without this join every Cloud PC lands in encryption reports as notEncrypted. If the
        # devices cache is missing the set stays empty and rows pass through untouched.
        $CloudPCIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        try {
            foreach ($Device in @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'ManagedDevices' -Fields 'id', 'isCloudPC', 'deviceType', 'chassisType', 'model', 'manufacturer')) {
                if ($Device.id -and (Test-CIPPCloudPCDevice -Device $Device)) { $null = $CloudPCIds.Add([string]$Device.id) }
            }
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Could not load the managed devices cache; Cloud PCs will not be marked platform-encrypted: $($_.Exception.Message)" -sev Warning
        }

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
                $IsCloudPC = $CloudPCIds.Contains([string]$_.id)
                $_ | Add-Member -NotePropertyName 'isCloudPC' -NotePropertyValue $IsCloudPC -Force
                # A distinct state rather than a rewrite to 'encrypted': the disk IS encrypted at
                # rest, but by the Azure platform, not by a BitLocker policy this report tracks.
                if ($IsCloudPC -and $_.encryptionState -eq 'notEncrypted') {
                    $_ | Add-Member -NotePropertyName 'encryptionState' -NotePropertyValue 'encryptedByPlatform' -Force
                }
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

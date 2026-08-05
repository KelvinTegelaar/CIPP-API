function Invoke-ExecGetRecoveryKey {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.Device.Read
    .DESCRIPTION
        Retrieves a device's disk encryption recovery key by device GUID. RecoveryKeyType selects BitLocker (the default) or FileVault. Returns a live recovery key in plain text; the retrieval is written to the CIPP audit log.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $GUID = $Request.Query.GUID ?? $Request.Body.GUID
    $RecoveryKeyType = $Request.Body.RecoveryKeyType ?? 'BitLocker'

    try {
        switch ($RecoveryKeyType) {
            'BitLocker' { $Result = Get-CIPPBitLockerKey -Device $GUID -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers }
            'FileVault' { $Result = Get-CIPPFileVaultKey -Device $GUID -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers }
            'BiosPassword' { $Result = Get-CIPPBiosPassword -Device $GUID -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers }
            default { throw "Invalid RecoveryKeyType specified: $RecoveryKeyType." }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })

}

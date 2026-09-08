Function Invoke-ExecMigrateOneDriveShortCuts {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers

    $TenantFilter = $Request.Body.tenantFilter
    $Username = $Request.Body.username
    if ($Username -is [psobject] -and $Username.value) { $Username = $Username.value }
    $ItemId = $Request.Body.id
    if ($ItemId -is [psobject] -and $ItemId.value) { $ItemId = $ItemId.value }

    try {
        $MigrateParams = @{
            Username     = $Username
            TenantFilter = $TenantFilter
            Headers      = $Headers
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$ItemId)) {
            $MigrateParams.ItemId = $ItemId
        }
        $Result = Invoke-CIPPMigrateOneDriveShortCuts @MigrateParams
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}

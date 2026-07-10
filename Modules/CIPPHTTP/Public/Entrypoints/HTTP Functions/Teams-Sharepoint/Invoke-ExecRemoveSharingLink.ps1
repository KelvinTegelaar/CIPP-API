function Invoke-ExecRemoveSharingLink {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    .DESCRIPTION
        Revokes a sharing link (or direct sharing grant) on a SharePoint or OneDrive item by
        deleting the permission from the drive item. Also removes the revoked link from the
        SharePointSharingLinks reporting cache so the sharing report reflects it immediately.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $DriveId = $Request.Body.DriveId
    $ItemId = $Request.Body.ItemId
    $PermissionId = $Request.Body.PermissionId
    $FileName = $Request.Body.FileName
    $CacheId = $Request.Body.CacheId

    try {
        if ([string]::IsNullOrWhiteSpace($DriveId) -or [string]::IsNullOrWhiteSpace($ItemId) -or [string]::IsNullOrWhiteSpace($PermissionId)) {
            throw 'DriveId, ItemId and PermissionId are required.'
        }

        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/drives/$DriveId/items/$ItemId/permissions/$PermissionId" -tenantid $TenantFilter -type DELETE -asapp $true

        # Best effort: drop the revoked link from the reporting cache so the report updates without a full sync.
        if (-not [string]::IsNullOrWhiteSpace($CacheId)) {
            try {
                Remove-CIPPDbItem -TenantFilter $TenantFilter -Type 'SharePointSharingLinks' -ItemId $CacheId
            } catch {
                Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Revoked sharing link but could not update the reporting cache: $($_.Exception.Message)" -sev Warning
            }
        }

        $Result = "Successfully revoked sharing link$(if ($FileName) { " for $FileName" })."
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to revoke sharing link$(if ($FileName) { " for $FileName" }). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{'Results' = $Result }
        })
}

function Invoke-ExecEditCalendarPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Headers = $Request.Headers


    # Extract parameters from query or body
    $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
    $UserID = $Request.Query.userid ?? $Request.Body.userid
    $UserToGetPermissions = $Request.Query.UserToGetPermissions ?? $Request.Body.UserToGetPermissions.value
    $Permissions = $Request.Query.Permissions ?? $Request.Body.Permissions.value
    $FolderName = $Request.Query.FolderName ?? $Request.Body.FolderName
    $RemoveAccess = $Request.Query.RemoveAccess ?? $Request.Body.RemoveAccess.value
    $CanViewPrivateItems = $Request.Query.CanViewPrivateItems ?? $Request.Body.CanViewPrivateItems

    try {
        if ($RemoveAccess) {
            $Result = Set-CIPPCalendarPermission -Headers $Headers -UserID $UserID -FolderName $FolderName -RemoveAccess $RemoveAccess -TenantFilter $TenantFilter
        } else {
            $Result = Set-CIPPCalendarPermission -Headers $Headers -UserID $UserID -FolderName $FolderName -TenantFilter $TenantFilter -UserToGetPermissions $UserToGetPermissions -Permissions $Permissions -CanViewPrivateItems $CanViewPrivateItems
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        Write-Warning "Error in ExecEditCalendarPermissions: $($_.Exception.Message)"
        Write-Information $_.InvocationInfo.PositionMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })
}

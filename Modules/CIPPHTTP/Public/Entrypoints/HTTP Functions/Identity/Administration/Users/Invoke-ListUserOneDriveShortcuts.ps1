Function Invoke-ListUserOneDriveShortcuts {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    .DESCRIPTION
        Lists OneDrive remoteItem shortcuts for a user from the drive root and the Shortcuts folder.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    $UserId = $Request.Query.userId
    $Username = $Request.Query.userPrincipalName

    if ([string]::IsNullOrWhiteSpace($Username) -and -not [string]::IsNullOrWhiteSpace($UserId)) {
        $User = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$UserId`?`$select=userPrincipalName" -tenantid $TenantFilter -asapp $true
        $Username = $User.userPrincipalName
    }

    if ([string]::IsNullOrWhiteSpace($Username)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @(@{ Results = 'userPrincipalName or userId is required' })
            })
    }

    $PreferHeaders = @{ Prefer = 'Include-Feature=AddToOneDrive' }
    $EscapedUser = [System.Uri]::EscapeDataString($Username)
    $Select = 'id,name,remoteItem,parentReference,createdDateTime,lastModifiedDateTime'

    $Results = [System.Collections.Generic.List[object]]::new()

    try {
        $RootChildren = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$EscapedUser/drive/root/children?`$select=$Select" -tenantid $TenantFilter -asapp $true -extraHeaders $PreferHeaders)
        foreach ($Item in ($RootChildren | Where-Object { $_.remoteItem })) {
            $Location = if ($Item.parentReference.path -match '/Shortcuts(/|$)') { 'Shortcuts folder' } else { 'OneDrive root' }
            $Results.Add([PSCustomObject]@{
                    id                = $Item.id
                    name              = $Item.name
                    location          = $Location
                    siteUrl           = $Item.remoteItem.sharepointIds.siteUrl
                    remoteItemId      = $Item.remoteItem.id
                    remoteDriveId     = $Item.remoteItem.parentReference.driveId
                    createdDateTime   = $Item.createdDateTime
                    lastModifiedDateTime = $Item.lastModifiedDateTime
                    userPrincipalName = $Username
                    userId            = $UserId
                })
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        if ($ErrorMessage.NormalizedError -match 'itemNotFound|ResourceNotFound|404|does not have a drive|no drive') {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = @()
                })
        }
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @(@{ Results = "Could not list OneDrive root shortcuts for $Username : $($ErrorMessage.NormalizedError)" })
            })
    }

    try {
        $ShortcutChildren = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$EscapedUser/drive/special/shortcuts/children?`$select=$Select" -tenantid $TenantFilter -asapp $true -extraHeaders $PreferHeaders)
        foreach ($Item in $ShortcutChildren) {
            # Avoid duplicates if root listing already returned Shortcuts children
            if ($Results.id -contains $Item.id) { continue }
            $Results.Add([PSCustomObject]@{
                    id                = $Item.id
                    name              = $Item.name
                    location          = 'Shortcuts folder'
                    siteUrl           = $Item.remoteItem.sharepointIds.siteUrl
                    remoteItemId      = $Item.remoteItem.id
                    remoteDriveId     = $Item.remoteItem.parentReference.driveId
                    createdDateTime   = $Item.createdDateTime
                    lastModifiedDateTime = $Item.lastModifiedDateTime
                    userPrincipalName = $Username
                    userId            = $UserId
                })
        }
    } catch {
        # special/shortcuts may 404 when the folder has never been created — treat as empty
        $ErrorMessage = Get-CippException -Exception $_
        if ($ErrorMessage.NormalizedError -notmatch 'itemNotFound|ResourceNotFound|404|special') {
            Write-LogMessage -API 'ListUserOneDriveShortcuts' -headers $Request.Headers -message "Could not list Shortcuts folder for $Username : $($ErrorMessage.NormalizedError)" -Sev 'Warning' -LogData $ErrorMessage
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Results)
        })
}

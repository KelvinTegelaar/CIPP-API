
function New-CIPPOneDriveShortCut {
    [CmdletBinding()]
    param (
        $username,
        $userid,
        $URL,
        $TenantFilter,
        $APIName = 'Create OneDrive shortcut',
        $ExecutingUser
    )
    Write-Host "Received $username and $userid. We're using $url and $TenantFilter"
    try {
        $SiteInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/sites/' -tenantid $TenantFilter -asapp $true | Where-Object -Property weburl -EQ $url
        $ListItemUniqueId = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$($siteInfo.id)/drive?`$select=SharepointIds" -tenantid $TenantFilter -asapp $true).SharePointIds
        $body = [PSCustomObject]@{
            name                                = "$($SiteInfo.displayName)"
            remoteItem                          = @{
                sharepointIds = @{
                    listId           = $($ListItemUniqueId.listid)
                    listItemUniqueId = 'root'
                    siteId           = $($ListItemUniqueId.siteId)
                    siteUrl          = $($ListItemUniqueId.siteUrl)
                    webId            = $($ListItemUniqueId.webId)
                }
            }
            '@microsoft.graph.conflictBehavior' = 'rename'
        } | ConvertTo-Json -Depth 10
        New-GraphPOSTRequest -method POST "https://graph.microsoft.com/beta/users/$username/drive/root/children" -body $body -tenantid $TenantFilter -asapp $true
        Write-LogMessage -API $APIName -user $ExecutingUser -message "Created OneDrive shortcut called $($SiteInfo.displayName) for $($username)" -Sev 'info'
        return "Created OneDrive Shortcut for $username called $($SiteInfo.displayName) "
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $ExecutingUser -API $APIName -message "Could not add Onedrive shortcut to $username : $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return "Could not add Onedrive shortcut to $username : $($ErrorMessage.NormalizedError)"
    }
}



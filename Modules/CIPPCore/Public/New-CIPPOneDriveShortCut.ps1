
function New-CIPPOneDriveShortCut {
    [CmdletBinding()]
    param (
        $Username,
        $UserId,
        $URL,
        $TenantFilter,
        $APIName = 'Create OneDrive shortcut',
        $Headers
    )
    Write-Host "Received $Username and $UserId. We're using $URL and $TenantFilter"
    try {
        $SiteInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/sites/' -tenantid $TenantFilter -asapp $true | Where-Object -Property weburl -EQ $URL
        $ListItemUniqueId = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$($siteInfo.id)/drive?`$select=SharepointIds" -tenantid $TenantFilter -asapp $true).SharePointIds
        $body = [PSCustomObject]@{
            name                                = 'Documents'
            remoteItem                          = @{
                SharepointIds = @{
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
        Write-LogMessage -API $APIName -headers $Headers -message "Created OneDrive shortcut called $($SiteInfo.displayName) for $($username)" -Sev 'info'
        return "Successfully created OneDrive Shortcut for $username called $($SiteInfo.displayName) "
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Could not add Onedrive shortcut to $username : $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        throw $Result
    }
}



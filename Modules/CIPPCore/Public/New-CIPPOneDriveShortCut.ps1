function New-CIPPOneDriveShortCut {
    [CmdletBinding()]
    param (
        $Username,
        $UserId,
        $URL,
        $LibraryId,
        $TenantFilter,
        $APIName = 'Create OneDrive shortcut',
        $Headers
    )

    try {
        $SiteInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/sites/' -tenantid $TenantFilter -asapp $true | Where-Object -Property weburl -EQ $URL

        if (!$SiteInfo) {
            throw "Could not find site with URL: $URL"
        }

        # Extract individual site IDs
        $SiteIdParts = $SiteInfo.id -split ','
        $SiteGuid = $SiteIdParts[1]
        $WebGuid = $SiteIdParts[2]

        if ($LibraryId) {
            # Get specific document library
            $AllDrives = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$SiteGuid/drives" -tenantid $TenantFilter -asapp $true
            $SelectedDrive = $AllDrives | Where-Object { $_.id -eq $LibraryId }

            if (!$SelectedDrive) {
                throw "Could not find drive with ID: $LibraryId in site $SiteGuid"
            }

            # Get SharePoint list information by searching for the library name
            $Lists = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$SiteGuid/lists?`$filter=displayName eq '$($SelectedDrive.name)'" -tenantid $TenantFilter -asapp $true

            if ($Lists -and $Lists.Count -gt 0) {
                $TargetList = $Lists[0]
                $ListItemUniqueId = @{
                    listId              = $TargetList.id
                    listItemUniqueId    = 'root'
                    siteId              = $SiteGuid
                    siteUrl             = $URL
                    webId               = $WebGuid
                }
                $LibraryName = $SelectedDrive.name
            } else {
                throw "Could not find SharePoint list for library: $($SelectedDrive.name)"
            }
        } else {
            # Use default Documents library
            $DriveInfo = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$SiteGuid/drive?`$select=SharepointIds,name" -tenantid $TenantFilter -asapp $true
            $ListItemUniqueId = $DriveInfo.SharePointIds
            $LibraryName = 'Documents'
        }

        # Validate required SharePoint IDs
        if (!$ListItemUniqueId.listId -or !$ListItemUniqueId.siteId) {
            throw "Missing required SharePoint IDs. ListId: $($ListItemUniqueId.listId), SiteId: $($ListItemUniqueId.siteId)"
        }

        # Create the OneDrive shortcut
        $body = [PSCustomObject]@{
            name = $LibraryName
            remoteItem = @{
                sharepointIds = @{
                    listId           = $($ListItemUniqueId.listid)
                    listItemUniqueId = if ($ListItemUniqueId.listItemUniqueId) { $ListItemUniqueId.listItemUniqueId } else { 'root' }
                    siteId           = $($ListItemUniqueId.siteId)
                    siteUrl          = if ($ListItemUniqueId.siteUrl) { $ListItemUniqueId.siteUrl } else { $URL }
                    webId            = if ($ListItemUniqueId.webId) { $ListItemUniqueId.webId } else { $WebGuid }
                }
            }
            '@microsoft.graph.conflictBehavior' = 'rename'
        } | ConvertTo-Json -Depth 10
        New-GraphPOSTRequest -method POST "https://graph.microsoft.com/beta/users/$Username/drive/root/children" -body $Body -tenantid $TenantFilter -asapp $true
        Write-LogMessage -API $APIName -headers $Headers -message "Created OneDrive shortcut called $LibraryName for $($Username)" -Sev 'info'
        return "Successfully created OneDrive Shortcut for $Username called $LibraryName"

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Could not add Onedrive shortcut to $Username : $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        throw $Result
    }
}

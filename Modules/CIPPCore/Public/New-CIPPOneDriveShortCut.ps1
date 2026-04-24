
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
        # Unwrap SharePoint browser URLs — e.g. AllItems.aspx?id=... or onedrive.aspx?id=...
        # The `id` query parameter holds the server-relative path to the folder, URL-encoded.
        if ($URL -match '[?&]id=([^&]+)') {
            $ServerRelativePath = [Uri]::UnescapeDataString($matches[1])
            $ParsedUri = [System.Uri]$URL
            $URL = "$($ParsedUri.Scheme)://$($ParsedUri.Host)$ServerRelativePath"
            Write-Host "Resolved browser URL to: $URL"
        }

        # Find site by prefix match (longest match wins — handles subsites correctly)
        $SiteInfo = (New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/sites/' -tenantid $TenantFilter -asapp $true) |
            Where-Object { $URL -like "$($_.weburl.TrimEnd('/'))/*" -or $URL -eq $_.weburl.TrimEnd('/') } |
            Sort-Object { $_.weburl.Length } -Descending |
            Select-Object -First 1

        if (-not $SiteInfo) {
            throw "Could not find a SharePoint site matching URL: $URL"
        }

        # Extract whatever comes after the site URL (library name + optional folder path)
        $RelativePath = $URL.Substring($SiteInfo.weburl.TrimEnd('/').Length).TrimStart('/')

        if ([string]::IsNullOrWhiteSpace($RelativePath)) {
            # ── Root shortcut (original behaviour) ──────────────────────────────
            $SPIds = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$($SiteInfo.id)/drive?`$select=SharepointIds" -tenantid $TenantFilter -asapp $true).SharePointIds
            $body = [PSCustomObject]@{
                name                                = 'Documents'
                remoteItem                          = @{
                    sharepointIds = @{
                        listId           = $SPIds.listid
                        listItemUniqueId = 'root'
                        siteId           = $SPIds.siteId
                        siteUrl          = $SPIds.siteUrl
                        webId            = $SPIds.webId
                    }
                }
                '@microsoft.graph.conflictBehavior' = 'rename'
            } | ConvertTo-Json -Depth 10
            $ShortcutDisplayName = $SiteInfo.displayName
        } else {
            # ── Subfolder shortcut ───────────────────────────────────────────────
            # Split "SharedDocuments/Folder123" into library name and optional subfolder
            $PathParts = $RelativePath -split '/'
            $LibraryName = [Uri]::UnescapeDataString($PathParts[0])
            $FolderPath = if ($PathParts.Count -gt 1) {
                ($PathParts[1..($PathParts.Count - 1)] | ForEach-Object { [Uri]::UnescapeDataString($_) }) -join '/'
            } else { $null }

            # Find the drive (document library) whose name matches the first path segment
            $Drives = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$($SiteInfo.id)/drives?`$select=id,name,webUrl" -tenantid $TenantFilter -asapp $true
            $Drive = $Drives | Where-Object {
                $_.name -eq $LibraryName -or
                [Uri]::UnescapeDataString($_.webUrl.TrimEnd('/').Split('/')[-1]) -eq $LibraryName
            } | Select-Object -First 1

            # Fall back to the default drive when no name match is found
            if (-not $Drive) {
                $Drive = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$($SiteInfo.id)/drive?`$select=id,name" -tenantid $TenantFilter -asapp $true
            }

            # Resolve the target driveItem — subfolder or library root
            if ($FolderPath) {
                $EncodedFolderPath = ($FolderPath -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
                $FolderItem = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/drives/$($Drive.id)/root:/$($EncodedFolderPath)?`$select=id,name,parentReference" -tenantid $TenantFilter -asapp $true
                $DisplayName = $FolderItem.name
            } else {
                $FolderItem = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/drives/$($Drive.id)/root?`$select=id,name" -tenantid $TenantFilter -asapp $true
                # Graph returns name='root' for a drive's root item — use the drive (library) name instead
                $DisplayName = $Drive.name
            }

            # POST body for subfolder uses driveItem.id + drive.id (not sharepointIds)
            $body = [PSCustomObject]@{
                name                                = $DisplayName
                remoteItem                          = @{
                    id              = $FolderItem.id
                    parentReference = @{ driveId = $Drive.id }
                }
                '@microsoft.graph.conflictBehavior' = 'rename'
            } | ConvertTo-Json -Depth 10
            $ShortcutDisplayName = "$($SiteInfo.displayName) / $DisplayName"
        }

        $null = New-GraphPOSTRequest -method POST "https://graph.microsoft.com/beta/users/$Username/drive/root/children" -body $Body -tenantid $TenantFilter -asapp $true
        Write-LogMessage -API $APIName -headers $Headers -message "Created OneDrive shortcut called $ShortcutDisplayName for $Username" -Sev 'info'
        return "Successfully created OneDrive Shortcut for $Username called $ShortcutDisplayName"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Could not add OneDrive shortcut to $Username : $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        throw $Result
    }
}

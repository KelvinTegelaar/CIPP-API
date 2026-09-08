
function New-CIPPOneDriveShortCut {
    [CmdletBinding()]
    param (
        $Username,
        $UserId,
        $URL,
        $TenantFilter,
        $APIName = 'Create OneDrive shortcut',
        $Headers,
        [ValidateSet('root', 'shortcuts')]
        [string]$Destination = 'root'
    )
    Write-Host "Received $Username and $UserId. We're using $URL and $TenantFilter (destination=$Destination)"
    try {
        $SPOTenant = Get-CIPPSPOTenant -TenantFilter $TenantFilter | Select-Object -First 1
        if ($SPOTenant.DisableAddToOneDrive -eq $true) {
            throw "Add shortcut to OneDrive is disabled for this tenant (DisableAddToOneDrive). Enable it via the 'Set Add Shortcuts To OneDrive button state' standard, or Set-SPOTenant -DisableAddShortcutsToOneDrive `$false."
        }

        # Unwrap SharePoint browser URLs — e.g. AllItems.aspx?id=... or onedrive.aspx?id=...
        # The `id` query parameter holds the server-relative path to the folder, URL-encoded.
        if ($URL -match '[?&]id=([^&]+)') {
            $ServerRelativePath = [Uri]::UnescapeDataString($matches[1])
            $ParsedUri = [System.Uri]$URL
            $URL = "$($ParsedUri.Scheme)://$($ParsedUri.Host)$ServerRelativePath"
            Write-Host "Resolved browser URL to: $URL"
        }

        # Strip list view paths so Shared Documents/Forms/AllItems.aspx resolves as the library
        $URL = ($URL -replace '/Forms/AllItems\.aspx.*$', '' -replace '/Forms/.*$', '').TrimEnd('/')

        $ParsedUri = [System.Uri]$URL
        $Hostname = $ParsedUri.Host
        $AbsPath = [Uri]::UnescapeDataString($ParsedUri.AbsolutePath).TrimEnd('/')

        # Resolve site via hostname:path (avoids paging gaps on GET /sites). Try longest path first for subsites.
        $SiteInfo = $null
        $Candidates = [System.Collections.Generic.List[string]]::new()
        if ($AbsPath -match '^/(sites|teams)/') {
            $Parts = @($AbsPath.TrimStart('/') -split '/')
            for ($i = $Parts.Length; $i -ge 2; $i--) {
                $Candidates.Add('/' + ($Parts[0..($i - 1)] -join '/'))
            }
        } elseif ($AbsPath -match '^(?<od>/personal/[^/]+)') {
            $Candidates.Add($Matches['od'])
        } else {
            throw "Could not parse a SharePoint site path from URL: $URL"
        }

        foreach ($Candidate in $Candidates) {
            try {
                $SiteInfo = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/${Hostname}:${Candidate}?`$select=id,displayName,webUrl" -tenantid $TenantFilter -asapp $true
                if ($SiteInfo.id) { break }
            } catch {
                $SiteInfo = $null
            }
        }

        if (-not $SiteInfo) {
            throw "Could not find a SharePoint site matching URL: $URL"
        }

        # Extract whatever comes after the site URL (library name + optional folder path)
        $SitePath = ([System.Uri]$SiteInfo.webUrl).AbsolutePath.TrimEnd('/')
        $RelativePath = if ($AbsPath.Length -gt $SitePath.Length -and $AbsPath.StartsWith($SitePath, [System.StringComparison]::OrdinalIgnoreCase)) {
            $AbsPath.Substring($SitePath.Length).TrimStart('/')
        } else {
            ''
        }

        if ([string]::IsNullOrWhiteSpace($RelativePath)) {
            # Same as the proven test script / HAR: default library via sites/{id}/drive sharePointIds
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
            $PathParts = $RelativePath -split '/'
            $LibraryName = [Uri]::UnescapeDataString($PathParts[0])
            $FolderPath = if ($PathParts.Count -gt 1) {
                ($PathParts[1..($PathParts.Count - 1)] | ForEach-Object { [Uri]::UnescapeDataString($_) }) -join '/'
            } else { $null }

            $Drives = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$($SiteInfo.id)/drives?`$select=id,name,webUrl" -tenantid $TenantFilter -asapp $true
            $Drive = $Drives | Where-Object {
                $_.name -eq $LibraryName -or
                [Uri]::UnescapeDataString($_.webUrl.TrimEnd('/').Split('/')[-1]) -eq $LibraryName
            } | Select-Object -First 1

            if (-not $Drive) {
                $Drive = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$($SiteInfo.id)/drive?`$select=id,name" -tenantid $TenantFilter -asapp $true
            }

            if ($FolderPath) {
                $EncodedFolderPath = ($FolderPath -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/'
                $FolderItem = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/drives/$($Drive.id)/root:/$($EncodedFolderPath)?`$select=id,name,parentReference" -tenantid $TenantFilter -asapp $true
                $DisplayName = $FolderItem.name
            } else {
                $FolderItem = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/drives/$($Drive.id)/root?`$select=id,name" -tenantid $TenantFilter -asapp $true
                $DisplayName = $Drive.name
            }

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

        # Proven path is root/children. special/shortcuts create is optional/undocumented.
        $PostUri = if ($Destination -eq 'shortcuts') {
            "https://graph.microsoft.com/beta/users/$Username/drive/special/shortcuts/children"
        } else {
            "https://graph.microsoft.com/beta/users/$Username/drive/root/children"
        }
        $DestinationLabel = if ($Destination -eq 'shortcuts') { 'Shortcuts folder' } else { 'OneDrive root' }

        $null = New-GraphPOSTRequest -uri $PostUri -body $body -tenantid $TenantFilter -asapp $true
        Write-LogMessage -API $APIName -headers $Headers -message "Created OneDrive shortcut called $ShortcutDisplayName for $Username in $DestinationLabel" -Sev 'info'
        return "Successfully created OneDrive Shortcut for $Username called $ShortcutDisplayName in $DestinationLabel"
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Could not add OneDrive shortcut to $Username : $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        throw $Result
    }
}

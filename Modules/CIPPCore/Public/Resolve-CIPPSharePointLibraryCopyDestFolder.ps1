function Resolve-CIPPSharePointLibraryCopyDestFolder {
    <#
    .SYNOPSIS
        Resolves (and optionally creates) a folder at the root of a destination document library.
    .DESCRIPTION
        Looks the name up at the library drive root. When -Create is set and nothing exists, the folder is
        created with conflictBehavior 'fail'; a concurrent create that loses the race re-reads and reuses
        the winner. An existing folder is always reused, never replaced or renamed, so re-running an archive
        copy lands in the same folder and file-level collisions are governed by NameConflictBehavior.
        An existing item with that name that is not a folder is an error.
        Without -Create, returns $null when the folder does not exist (used by preflight).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$SiteId,

        [Parameter(Mandatory = $true)]
        [string]$ListId,

        [Parameter(Mandatory = $true)]
        [string]$FolderName,

        [switch]$Create
    )

    $DriveRootUri = "https://graph.microsoft.com/v1.0/sites/$SiteId/lists/$ListId/drive/root"
    $EscapedName = [uri]::EscapeDataString($FolderName)
    $ExistingItemUri = "$DriveRootUri`:/$EscapedName`?`$select=id,name,webUrl,folder,file"

    $ToResult = {
        param($Item, [bool]$Created)
        if (-not $Item.folder) {
            throw "An item named '$FolderName' already exists at the root of the destination library and is not a folder."
        }
        [PSCustomObject]@{
            ItemId  = $Item.id
            Name    = $Item.name
            WebUrl  = $Item.webUrl
            Created = $Created
        }
    }

    $Existing = $null
    try {
        $Existing = New-GraphGetRequest -uri $ExistingItemUri -tenantid $TenantFilter -asapp $true
    } catch {
        # 404 means the folder does not exist yet, which is the normal path.
        $Existing = $null
    }
    if ($Existing.id) {
        return (& $ToResult $Existing $false)
    }

    if (-not $Create) {
        return $null
    }

    $Body = ConvertTo-Json -Compress -InputObject @{
        name                                = $FolderName
        folder                              = @{}
        '@microsoft.graph.conflictBehavior' = 'fail'
    }

    try {
        $NewFolder = New-GraphPOSTRequest -uri "$DriveRootUri/children" -tenantid $TenantFilter -type POST -body $Body -AsApp $true
        return (& $ToResult $NewFolder $true)
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        # NormalizedError carries Graph's error.message ("Name already exists"), not its code, so the
        # raw body is checked too: that is where 'nameAlreadyExists' survives.
        $ConflictText = "$($ErrorMessage.NormalizedError) $($ErrorMessage.RawError)"
        if ($ConflictText -match 'nameAlreadyExists|already exists|conflict|409') {
            $Existing = $null
            try {
                $Existing = New-GraphGetRequest -uri $ExistingItemUri -tenantid $TenantFilter -asapp $true
            } catch {
                $Existing = $null
            }
            if ($Existing.id) {
                return (& $ToResult $Existing $false)
            }
        }
        throw "Failed to create destination folder '$FolderName': $($ErrorMessage.NormalizedError)"
    }
}

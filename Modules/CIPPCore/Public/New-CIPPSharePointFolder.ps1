function New-CIPPSharePointFolder {
    <#
    .SYNOPSIS
    Create a folder at the root of a Team's default Documents library

    .DESCRIPTION
    Creates a folder as a sibling of the General channel folder under the team's Documents
    drive root via Microsoft Graph. If a folder (or item) with the same name already exists
    it is returned instead. The reserved name "General" is refused.

    .PARAMETER GroupId
    The Team / M365 group id whose default drive (Documents) hosts the folder

    .PARAMETER FolderName
    Name of the folder to create at the drive root

    .PARAMETER TenantFilter
    The tenant the Team belongs to
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupId,

        [Parameter(Mandatory = $true)]
        [string]$FolderName,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        $APIName = 'Create SharePoint Folder',
        $Headers
    )

    $TrimmedName = $FolderName.Trim()
    if (-not $TrimmedName) {
        throw 'Folder name is required.'
    }
    if ($TrimmedName -ieq 'General') {
        throw 'Folder name "General" is reserved for the default channel folder.'
    }

    $DriveRootChildrenUri = "https://graph.microsoft.com/v1.0/groups/$GroupId/drive/root/children"
    $EscapedPathName = [uri]::EscapeDataString($TrimmedName)
    $ExistingItemUri = "https://graph.microsoft.com/v1.0/groups/$GroupId/drive/root:/${EscapedPathName}"

    # Wait briefly for the Documents drive after Team provision.
    $DriveReady = $false
    $Attempts = 0
    do {
        $Attempts++
        try {
            $null = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/groups/$GroupId/drive?`$select=id" -tenantid $TenantFilter -AsApp $true
            $DriveReady = $true
        } catch {
            if ($Attempts -lt 8) { Start-Sleep -Seconds 5 }
        }
    } while (-not $DriveReady -and $Attempts -lt 8)

    if (-not $DriveReady) {
        throw "Documents drive for team $GroupId was not available yet. Folder '$TrimmedName' was not created."
    }

    # Idempotency: reuse an existing root item with this name.
    try {
        $Existing = New-GraphGetRequest -uri "$ExistingItemUri`?`$select=id,name,folder" -tenantid $TenantFilter -AsApp $true
        if ($Existing.id) {
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Folder $TrimmedName already exists on team $GroupId Documents root, reusing it." -sev Info
            return [PSCustomObject]@{
                ItemId  = $Existing.id
                Name    = $Existing.name
                Created = $false
            }
        }
    } catch {
        # 404 means the folder does not exist yet, which is the normal path.
    }

    if (-not $PSCmdlet.ShouldProcess($TrimmedName, "Create folder on team $GroupId Documents root")) { return }

    try {
        $Body = ConvertTo-Json -Compress -InputObject @{
            name                                   = $TrimmedName
            folder                                 = @{}
            '@microsoft.graph.conflictBehavior'    = 'fail'
        }
        $NewFolder = New-GraphPostRequest -uri $DriveRootChildrenUri -tenantid $TenantFilter -type POST -body $Body -AsApp $true
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Successfully created folder $TrimmedName on team $GroupId Documents root" -sev Info
        return [PSCustomObject]@{
            ItemId  = $NewFolder.id
            Name    = $NewFolder.name
            Created = $true
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        # Race / concurrent create: treat name conflict as success via re-fetch.
        if ($ErrorMessage.NormalizedError -match 'nameAlreadyExists|conflict|409') {
            try {
                $Existing = New-GraphGetRequest -uri "$ExistingItemUri`?`$select=id,name,folder" -tenantid $TenantFilter -AsApp $true
                if ($Existing.id) {
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Folder $TrimmedName already exists on team $GroupId Documents root, reusing it." -sev Info
                    return [PSCustomObject]@{
                        ItemId  = $Existing.id
                        Name    = $Existing.name
                        Created = $false
                    }
                }
            } catch {}
        }
        $Result = "Failed to create folder $TrimmedName on team $GroupId Documents root. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        throw $Result
    }
}

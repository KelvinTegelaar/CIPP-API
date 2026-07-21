function New-CIPPSharePointLibrary {
    <#
    .SYNOPSIS
    Create a document library on a SharePoint site

    .DESCRIPTION
    Creates a document library (BaseTemplate 101) on the given site via the SharePoint REST
    API. If a list with the same title already exists it is returned instead, so deploys are
    idempotent.

    .PARAMETER SiteUrl
    The full URL of the site to create the library on

    .PARAMETER LibraryName
    The title of the document library

    .PARAMETER Description
    The description of the document library

    .PARAMETER TenantFilter
    The tenant the site belongs to
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SiteUrl,

        [Parameter(Mandatory = $true)]
        [string]$LibraryName,

        [string]$Description = '',

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        $APIName = 'Create SharePoint Library',
        $Headers
    )

    $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
    $Scope = "$($SharePointInfo.SharePointUrl)/.default"
    $JsonAccept = @{ Accept = 'application/json;odata=nometadata' }
    $BaseUri = "$($SiteUrl.TrimEnd('/'))/_api"

    # Idempotency: return the existing library when one with this title is already present.
    $EscapedTitle = $LibraryName -replace "'", "''"
    try {
        $Existing = New-GraphGetRequest -uri "$BaseUri/web/lists/GetByTitle('$EscapedTitle')?`$select=Id,Title" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
        if ($Existing.Id) {
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Library $LibraryName already exists on $SiteUrl, reusing it." -sev Info
            return [PSCustomObject]@{
                ListId  = $Existing.Id
                Title   = $Existing.Title
                Created = $false
            }
        }
    } catch {
        # 404 means the library does not exist yet, which is the normal path.
    }

    if (-not $PSCmdlet.ShouldProcess($LibraryName, "Create document library on $SiteUrl")) { return }

    try {
        $Body = ConvertTo-Json -Compress -InputObject @{
            BaseTemplate = 101
            Title        = $LibraryName
            Description  = $Description
        }
        $NewList = New-GraphPostRequest -uri "$BaseUri/web/lists" -tenantid $TenantFilter -scope $Scope -type POST -body $Body -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Successfully created document library $LibraryName on $SiteUrl" -sev Info
        return [PSCustomObject]@{
            ListId  = $NewList.Id
            Title   = $NewList.Title
            Created = $true
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create document library $LibraryName on $SiteUrl. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        throw $Result
    }
}

function Resolve-CIPPSharePointPermissionScope {
    <#
    .SYNOPSIS
    Resolve the SharePoint REST context for a permission scope

    .DESCRIPTION
    Builds everything needed to read or change role assignments on a SharePoint scope: the site
    base URI, the token scope, the odata headers and the role assignment URI. Supplying ListId
    targets a document library, omitting it targets the site root web.

    Role assignments can only be changed on a scope that holds its own permissions. With
    -EnsureUniqueRoleAssignments a library that still inherits has its inheritance broken first
    (copying the current assignments), so the change stays scoped to that library instead of
    silently altering the whole site. Site root webs always hold their own assignments, so
    nothing is broken there.

    .PARAMETER SiteUrl
    The full URL of the site

    .PARAMETER ListId
    Optional list/library id. When omitted the site root web is targeted.

    .PARAMETER TenantFilter
    The tenant the site belongs to

    .PARAMETER EnsureUniqueRoleAssignments
    Break inheritance (copying the existing assignments) when the library still inherits
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SiteUrl,

        [string]$ListId,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [switch]$EnsureUniqueRoleAssignments
    )

    $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
    $Scope = "$($SharePointInfo.SharePointUrl)/.default"
    $JsonAccept = @{ Accept = 'application/json;odata=nometadata' }
    $BaseUri = "$($SiteUrl.TrimEnd('/'))/_api"

    $IsLibrary = -not [string]::IsNullOrWhiteSpace($ListId)
    $ScopeUri = if ($IsLibrary) { "$BaseUri/web/lists(guid'$ListId')" } else { "$BaseUri/web" }

    $BrokeInheritance = $false
    if ($IsLibrary) {
        $ListInfo = New-GraphGetRequest -uri "$ScopeUri`?`$select=HasUniqueRoleAssignments,Title" -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true
        $HasUnique = [bool]$ListInfo.HasUniqueRoleAssignments
        $TargetLabel = if ($ListInfo.Title) { "library '$($ListInfo.Title)'" } else { "library $ListId" }

        if (-not $HasUnique -and $EnsureUniqueRoleAssignments.IsPresent) {
            if ($PSCmdlet.ShouldProcess($TargetLabel, 'Break role inheritance')) {
                $null = New-GraphPostRequest -uri "$ScopeUri/breakroleinheritance(copyRoleAssignments=true,clearSubscopes=false)" -tenantid $TenantFilter -scope $Scope -type POST -body '{}' -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
                $HasUnique = $true
                $BrokeInheritance = $true
            }
        }
    } else {
        # A site collection root web always holds its own assignments.
        $HasUnique = $true
        $TargetLabel = 'site root'
    }

    return [PSCustomObject]@{
        BaseUri                  = $BaseUri
        Scope                    = $Scope
        Headers                  = $JsonAccept
        ScopeUri                 = $ScopeUri
        AssignmentUri            = "$ScopeUri/roleassignments"
        IsLibrary                = $IsLibrary
        TargetLabel              = $TargetLabel
        HasUniqueRoleAssignments = $HasUnique
        BrokeInheritance         = $BrokeInheritance
    }
}

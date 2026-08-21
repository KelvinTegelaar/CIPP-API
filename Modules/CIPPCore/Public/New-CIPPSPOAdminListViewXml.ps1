function New-CIPPSPOAdminListViewXml {
    <#
    .SYNOPSIS
    Build ViewXml for SPO.Tenant/RenderAdminListData (Active sites catalog).

    .DESCRIPTION
    Constructs a CAML View for the undocumented SharePoint admin aggregated site list
    (DO_NOT_DELETE_SPLIST_TENANTADMIN_AGGREGATED_SITECO / RenderAdminListData).
    Filters and ViewFields are reverse-engineered from the Active sites admin UI;
    there is no public support SLA.

    .PARAMETER ViewFields
    FieldRef names to select. Validated against a known allowlist.

    .PARAMETER SiteFlags
    Integer SiteFlags values for an In filter (Active sites defaults).

    .PARAMETER ExcludeDeleted
    When true, requires TimeDeleted to be null.

    .PARAMETER ExcludeState
    When set, adds Neq State. Pass $null to omit.

    .PARAMETER ExcludeTemplates
    TemplateName values to exclude via Neq. Mutually exclusive with IncludeTemplates.

    .PARAMETER IncludeTemplates
    TemplateName values to include via In. Mutually exclusive with ExcludeTemplates.

    .PARAMETER OrderBy
    Field to sort by (must be on the allowlist).

    .PARAMETER OrderAscending
    Sort direction.

    .PARAMETER RowLimit
    Paged RowLimit (default 200; admin UI uses 30).

    .PARAMETER ExtraWhereXml
    Optional raw CAML fragment AND-ed into Where for advanced filters without a full ViewXml.

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding()]
    param(
        [string[]]$ViewFields = @(
            'Title'
            'SiteUrl'
            'SiteId'
            'StorageUsed'
            'StorageQuota'
            'NumOfFiles'
            'TemplateName'
            'TimeCreated'
            'GroupId'
            'SiteOwnerName'
            'SiteOwnerEmail'
            'ExternalSharing'
            'LastActivityOn'
            'SiteFlags'
        ),

        [int[]]$SiteFlags = @(0, 1, 4, 5, 8, 9, 12, 13),

        [bool]$ExcludeDeleted = $true,

        [AllowNull()]
        [object]$ExcludeState = 0,

        [string[]]$ExcludeTemplates = @('TEAMCHANNEL#0', 'TEAMCHANNEL#1'),

        [string[]]$IncludeTemplates = @(),

        [string]$OrderBy = 'Title',

        [bool]$OrderAscending = $true,

        [ValidateRange(1, 5000)]
        [int]$RowLimit = 200,

        [string]$ExtraWhereXml
    )

    # Conservative allowlist — expand when a caller needs a field the aggregated list exposes.
    $AllowedFields = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($Name in @(
            'Title', 'SiteUrl', 'SiteId', 'StorageUsed', 'StorageQuota', 'NumOfFiles',
            'TemplateName', 'TimeCreated', 'GroupId', 'SiteOwnerName', 'SiteOwnerEmail',
            'ExternalSharing', 'LastActivityOn', 'SiteFlags', 'CreatedBy', 'HubSiteId',
            'IsHubSite', 'SensitivityLabel', 'State', 'TimeDeleted', 'RelatedGroupId'
        )) {
        [void]$AllowedFields.Add($Name)
    }

    if (-not $ViewFields -or $ViewFields.Count -eq 0) {
        throw 'ViewFields must contain at least one field.'
    }
    foreach ($Field in $ViewFields) {
        if (-not $AllowedFields.Contains($Field)) {
            throw "ViewFields value '$Field' is not on the RenderAdminListData allowlist."
        }
    }
    if (-not $AllowedFields.Contains($OrderBy)) {
        throw "OrderBy value '$OrderBy' is not on the RenderAdminListData allowlist."
    }

    $HasExcludeTemplates = @($ExcludeTemplates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0
    $HasIncludeTemplates = @($IncludeTemplates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0
    if ($HasExcludeTemplates -and $HasIncludeTemplates) {
        throw 'Specify ExcludeTemplates or IncludeTemplates, not both.'
    }

    function Join-CamlAnd {
        param([string[]]$Parts)
        $Parts = @($Parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($Parts.Count -eq 0) { return $null }
        if ($Parts.Count -eq 1) { return $Parts[0] }
        $Acc = $Parts[0]
        for ($i = 1; $i -lt $Parts.Count; $i++) {
            $Acc = "<And>$Acc$($Parts[$i])</And>"
        }
        return $Acc
    }

    $WhereParts = [System.Collections.Generic.List[string]]::new()

    if ($ExcludeDeleted) {
        [void]$WhereParts.Add('<IsNull><FieldRef Name="TimeDeleted"/></IsNull>')
    }

    if ($null -ne $SiteFlags -and $SiteFlags.Count -gt 0) {
        $FlagValues = ($SiteFlags | ForEach-Object {
                "<Value Type='Integer'>$([int]$_)</Value>"
            }) -join ''
        [void]$WhereParts.Add("<In><FieldRef Name=`"SiteFlags`"/><Values>$FlagValues</Values></In>")
    }

    if ($null -ne $ExcludeState -and "$ExcludeState" -ne '') {
        $StateInt = [int]$ExcludeState
        [void]$WhereParts.Add("<Neq><FieldRef Name='State'/><Value Type='Integer'>$StateInt</Value></Neq>")
    }

    if ($HasExcludeTemplates) {
        $TemplateNeqs = foreach ($Template in $ExcludeTemplates) {
            if ([string]::IsNullOrWhiteSpace($Template)) { continue }
            $Escaped = [System.Security.SecurityElement]::Escape($Template)
            "<Neq><FieldRef Name='TemplateName'/><Value Type='Text'>$Escaped</Value></Neq>"
        }
        $TemplateBlock = Join-CamlAnd -Parts @($TemplateNeqs)
        if ($TemplateBlock) {
            [void]$WhereParts.Add($TemplateBlock)
        }
    } elseif ($HasIncludeTemplates) {
        $TemplateValues = ($IncludeTemplates | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
                $Escaped = [System.Security.SecurityElement]::Escape($_)
                "<Value Type='Text'>$Escaped</Value>"
            }) -join ''
        [void]$WhereParts.Add("<In><FieldRef Name=`"TemplateName`"/><Values>$TemplateValues</Values></In>")
    }

    if (-not [string]::IsNullOrWhiteSpace($ExtraWhereXml)) {
        [void]$WhereParts.Add($ExtraWhereXml.Trim())
    }

    $WhereInner = Join-CamlAnd -Parts @($WhereParts)
    $WhereXml = if ($WhereInner) { "<Where>$WhereInner</Where>" } else { '' }

    $AscendingAttr = if ($OrderAscending) { 'true' } else { 'false' }
    $OrderByEscaped = [System.Security.SecurityElement]::Escape($OrderBy)
    $OrderByXml = "<OrderBy><FieldRef Name='$OrderByEscaped' Ascending='$AscendingAttr' /></OrderBy>"

    $FieldRefs = ($ViewFields | ForEach-Object {
            $Name = [System.Security.SecurityElement]::Escape($_)
            "<FieldRef Name=`"$Name`"/>"
        }) -join ''

    return "<View><Query>$WhereXml$OrderByXml</Query><ViewFields>$FieldRefs</ViewFields><RowLimit Paged=`"TRUE`">$RowLimit</RowLimit></View>"
}

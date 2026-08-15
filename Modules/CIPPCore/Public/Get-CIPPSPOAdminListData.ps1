function Get-CIPPSPOAdminListData {
    <#
    .SYNOPSIS
    Page SPO.Tenant/RenderAdminListData (admin aggregated site catalog).

    .DESCRIPTION
    Calls the undocumented SharePoint admin RenderAdminListData endpoint used by Active sites.
    Builds ViewXml from structured parameters by default, or accepts a raw -ViewXml escape hatch.
    Returns flat admin list Row objects (all pages). Does not join Graph or map browser DTOs.

    Dotted numeric props (e.g. StorageUsed.) are an RLD quirk; -NormalizeRows copies them to
    undotted names when present.

    .PARAMETER TenantFilter
    Tenant to query.

    .PARAMETER Type
    Catalog kind: SharePoint (Active sites filters; default) or OneDrive (personal sites).
    Structured -Type OneDrive is not implemented yet and throws; use -ViewXml to probe.

    .PARAMETER ViewXml
    Raw ViewXml. When set, structured ViewXml parameters are ignored.

    .PARAMETER AdminUrl
    Optional SharePoint admin URL; resolved via Get-SharePointAdminLink when omitted.

    .PARAMETER DatesInUtc
    Passed to RenderAdminListData parameters.

    .PARAMETER MaxPages
    Abort if paging exceeds this many pages.

    .PARAMETER NormalizeRows
    Copy StorageUsed. / NumOfFiles. / etc. onto undotted property names.

    .FUNCTIONALITY
    Internal
    #>
    [CmdletBinding(DefaultParameterSetName = 'Structured')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [ValidateSet('SharePoint', 'OneDrive')]
        [string]$Type = 'SharePoint',

        [Parameter(ParameterSetName = 'ViewXml', Mandatory = $true)]
        [string]$ViewXml,

        [Parameter(ParameterSetName = 'Structured')]
        [string[]]$ViewFields,

        [Parameter(ParameterSetName = 'Structured')]
        [int[]]$SiteFlags,

        [Parameter(ParameterSetName = 'Structured')]
        [bool]$ExcludeDeleted = $true,

        [Parameter(ParameterSetName = 'Structured')]
        [AllowNull()]
        [object]$ExcludeState = 0,

        [Parameter(ParameterSetName = 'Structured')]
        [string[]]$ExcludeTemplates,

        [Parameter(ParameterSetName = 'Structured')]
        [string[]]$IncludeTemplates,

        [Parameter(ParameterSetName = 'Structured')]
        [string]$OrderBy = 'Title',

        [Parameter(ParameterSetName = 'Structured')]
        [bool]$OrderAscending = $true,

        [Parameter(ParameterSetName = 'Structured')]
        [ValidateRange(1, 5000)]
        [int]$RowLimit = 200,

        [Parameter(ParameterSetName = 'Structured')]
        [string]$ExtraWhereXml,

        [string]$AdminUrl,

        [bool]$DatesInUtc = $true,

        [ValidateRange(1, 5000)]
        [int]$MaxPages = 500,

        [bool]$NormalizeRows = $true
    )

    # OneDrive catalog ViewXml is not locked yet. Raw -ViewXml still works for discovery.
    if ($Type -eq 'OneDrive' -and $PSCmdlet.ParameterSetName -ne 'ViewXml') {
        throw 'Get-CIPPSPOAdminListData -Type OneDrive is not implemented yet. Pass -ViewXml to query personal sites, or use -Type SharePoint.'
    }

    if ([string]::IsNullOrWhiteSpace($AdminUrl)) {
        $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
        $AdminUrl = $SharePointInfo.AdminUrl
    }
    $AdminUrl = $AdminUrl.TrimEnd('/')

    if ($PSCmdlet.ParameterSetName -eq 'Structured') {
        $BuildParams = @{
            ExcludeDeleted  = $ExcludeDeleted
            ExcludeState    = $ExcludeState
            OrderBy         = $OrderBy
            OrderAscending  = $OrderAscending
            RowLimit        = $RowLimit
        }
        if ($PSBoundParameters.ContainsKey('ViewFields')) { $BuildParams['ViewFields'] = $ViewFields }
        if ($PSBoundParameters.ContainsKey('SiteFlags')) { $BuildParams['SiteFlags'] = $SiteFlags }
        if ($PSBoundParameters.ContainsKey('ExcludeTemplates')) { $BuildParams['ExcludeTemplates'] = $ExcludeTemplates }
        if ($PSBoundParameters.ContainsKey('IncludeTemplates')) { $BuildParams['IncludeTemplates'] = $IncludeTemplates }
        if ($PSBoundParameters.ContainsKey('ExtraWhereXml')) { $BuildParams['ExtraWhereXml'] = $ExtraWhereXml }
        $ViewXml = New-CIPPSPOAdminListViewXml @BuildParams
    }

    if ([string]::IsNullOrWhiteSpace($ViewXml)) {
        throw 'ViewXml is required (pass -ViewXml or use structured ViewFields/filter parameters).'
    }

    $AllRows = [System.Collections.Generic.List[object]]::new()
    $Paging = $null
    $PageGuard = 0

    do {
        $PageGuard++
        if ($PageGuard -gt $MaxPages) {
            throw "RenderAdminListData exceeded $MaxPages pages; aborting."
        }

        $Parameters = @{
            ViewXml    = $ViewXml
            DatesInUtc = $DatesInUtc
        }
        if (-not [string]::IsNullOrWhiteSpace($Paging)) {
            $Parameters['Paging'] = $Paging
        }
        $BodyObj = @{ parameters = $Parameters }

        $Page = New-GraphPOSTRequest -scope "$AdminUrl/.default" -tenantid $TenantFilter -uri "$AdminUrl/_api/SPO.Tenant/RenderAdminListData" -type 'POST' -body (ConvertTo-Json -Depth 8 -Compress -InputObject $BodyObj) -contentType 'application/json' -AddedHeaders @{ Accept = 'application/json;odata=verbose' } -AsApp $true -UseCertificate

        if ($Page -is [string]) {
            $Page = $Page | ConvertFrom-Json
        }
        if ($Page.d) {
            if ($Page.d.RenderAdminListData -is [string]) {
                $Page = $Page.d.RenderAdminListData | ConvertFrom-Json
            } elseif ($Page.d.RenderAdminListData) {
                $Page = $Page.d.RenderAdminListData
            } elseif ($Page.d.Row -or $Page.d.NextHref) {
                $Page = $Page.d
            }
        } elseif ($Page.RenderAdminListData -is [string]) {
            $Page = $Page.RenderAdminListData | ConvertFrom-Json
        } elseif ($Page.RenderAdminListData) {
            $Page = $Page.RenderAdminListData
        }

        foreach ($Row in @($Page.Row)) {
            if ($null -eq $Row) { continue }
            if ($NormalizeRows) {
                foreach ($Prop in @($Row.PSObject.Properties)) {
                    $Name = [string]$Prop.Name
                    if ($Name.EndsWith('.') -and $Name.Length -gt 1) {
                        $Plain = $Name.TrimEnd('.')
                        if (-not ($Row.PSObject.Properties.Name -contains $Plain)) {
                            $Row | Add-Member -NotePropertyName $Plain -NotePropertyValue $Prop.Value -Force
                        }
                    }
                }
            }
            [void]$AllRows.Add($Row)
        }

        $NextHref = [string]$Page.NextHref
        if ([string]::IsNullOrWhiteSpace($NextHref)) {
            $Paging = $null
        } elseif ($NextHref.Contains('?')) {
            $Paging = $NextHref.Split('?', 2)[1]
        } else {
            $Paging = $NextHref.TrimStart('?')
        }
    } while (-not [string]::IsNullOrWhiteSpace($Paging))

    return @($AllRows)
}

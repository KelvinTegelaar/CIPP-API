function ConvertTo-SPOUsageRootWebTemplate {
    <#
    .SYNOPSIS
        Map SPO admin TemplateName to Graph getSharePointSiteUsageDetail rootWebTemplate values.

    .DESCRIPTION
        RenderAdminListData returns template codes like GROUP#0 and STS#3. Cached SharePoint
        usage consumers (sharing report, SharePoint Sites actions) expect the friendly values
        from the Graph usage report, e.g. Group and Team Channel.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$TemplateName
    )

    if ([string]::IsNullOrWhiteSpace($TemplateName)) { return $null }

    $Trimmed = $TemplateName.Trim()
    if ($Trimmed -notmatch '#') { return $Trimmed }

    $Base = ($Trimmed -split '#', 2)[0].Trim()

    switch -Regex ($Base) {
        '^(?i)GROUP$' { return 'Group' }
        '^(?i)TEAMCHANNEL$' { return 'Team Channel' }
        '^(?i)STS$' { return 'STS' }
        '^(?i)SITEPAGEPUBLISHING$' { return 'Site Page Publishing' }
        '^(?i)APPCATALOG$' { return 'App Catalog Site' }
        '^(?i)REDIRECTSITE$' { return 'Redirect Site' }
        '^(?i)TENANTADMIN$' { return 'Tenant Admin Site' }
        '^(?i)SPSMSITEHOST$' { return 'My Site Host' }
        '^(?i)SRCHCEN$' { return 'Basic Search Center' }
        '^(?i)EDISC$' { return 'Compliance Policy Center' }
        '^(?i)POINTPUBLISHINGTOPIC$' { return 'SharePoint Online Tenant Fundamental Site' }
        default { return $Base }
    }
}

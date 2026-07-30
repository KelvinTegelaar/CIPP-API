function New-CIPPSharepointSite {
    <#
    .SYNOPSIS
    Create a new SharePoint site

    .DESCRIPTION
    Create a new SharePoint site using the Modern REST API

    .PARAMETER SiteName
    The name of the site

    .PARAMETER SiteDescription
    The description of the site

    .PARAMETER SiteOwner
    The username of the site owner

    .PARAMETER TemplateName
    The template to use for the site. Default is Communication

    .PARAMETER SiteDesign
    The design to use for the site. Default is Topic

    .PARAMETER WebTemplateExtensionId
    The web template extension ID to use

    .PARAMETER SensitivityLabel
    The Purview sensitivity label to apply to the site

    .PARAMETER Lcid
    SharePoint UI language LCID. Omit to keep the legacy English (1033) default used by
    Add Site. Pass 0 to use the tenant default (SharePoint Online root site language).
    Pass a positive LCID to force that language — must be a SharePoint Online site-creation
    language (same allowlist as the template builder). If 0 is passed and the root language
    cannot be read, site creation fails instead of falling back to English.

    .PARAMETER TenantFilter
    The tenant associated with the site

    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SiteName,

        [Parameter(Mandatory = $true)]
        [string]$SiteDescription,

        [Parameter(Mandatory = $true)]
        [string]$SiteOwner,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Communication', 'Team')]
        [string]$TemplateName = 'Communication',

        [Parameter(Mandatory = $false)]
        [ValidateSet('Topic', 'Showcase', 'Blank', 'Custom')]
        [string]$SiteDesign = 'Showcase',

        [Parameter(Mandatory = $false)]
        [ValidatePattern('(\{|\()?[A-Za-z0-9]{4}([A-Za-z0-9]{4}\-?){4}[A-Za-z0-9]{12}(\}|\()?')]
        [string]$WebTemplateExtensionId,

        [Parameter(Mandatory = $false)]
        [string]$SensitivityLabel,

        [string]$Classification,

        [Parameter(Mandatory = $false)]
        [int]$Lcid,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        $APIName = 'Create SharePoint Site',
        $Headers
    )

    # SharePoint Online site-creation UI languages (not full Windows LCIDs — e.g. en-GB 2057 is invalid).
    # Keep in sync with SITE_LANGUAGE_OPTIONS in CippSharePointTemplateBuilder.jsx.
    $AllowedSiteLcids = @(
        1025, 1026, 1027, 1028, 1029, 1030, 1031, 1032, 1033, 1035, 1036, 1037, 1038, 1040, 1041,
        1042, 1043, 1044, 1045, 1046, 1048, 1049, 1050, 1051, 1053, 1054, 1055, 1057, 1058, 1060,
        1061, 1062, 1063, 1066, 1069, 1081, 1086, 1087, 1106, 1110, 2052, 2070, 2074, 3082
    )

    $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
    $SitePath = $SiteName -replace ' ' -replace '[^A-Za-z0-9-]'
    $SiteUrl = "https://$($SharePointInfo.TenantName).sharepoint.com/sites/$SitePath"

    # Resolve site language:
    # - Explicit positive LCID → use it (must be in $AllowedSiteLcids)
    # - Explicit 0 (or negative) → tenant default. In SharePoint Online that is the root
    #   site language (https://{tenant}.sharepoint.com); there is no separate admin-center
    #   "default language" API (Graph sharepointSettings has timezone, not language).
    # - Parameter omitted → English (1033), preserving AddSite / bulk-create behaviour
    #
    # When tenant default is requested but the root language cannot be read, fail instead of
    # silently creating an English site on a non-English tenant.
    if ($PSBoundParameters.ContainsKey('Lcid')) {
        if ($Lcid -gt 0) {
            if ($Lcid -notin $AllowedSiteLcids) {
                $Result = "LCID $Lcid is not a supported SharePoint Online site language. Choose a language from the template builder list (or tenant default)."
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error
                throw $Result
            }
            $ResolvedLcid = $Lcid
        } else {
            $ResolvedLcid = 0
            $RootLanguageError = $null
            try {
                $JsonAccept = @{ Accept = 'application/json;odata=nometadata' }
                $RootWeb = New-GraphGetRequest -uri "https://$($SharePointInfo.TenantName).sharepoint.com/_api/web?`$select=Language" -tenantid $TenantFilter -scope "$($SharePointInfo.SharePointUrl)/.default" -extraHeaders $JsonAccept -UseCertificate -AsApp $true
                if ($RootWeb.Language -gt 0) {
                    $ResolvedLcid = [int]$RootWeb.Language
                }
            } catch {
                $RootLanguageError = $_.Exception.Message
            }
            if ($ResolvedLcid -le 0) {
                $Detail = if ($RootLanguageError) { $RootLanguageError } else { 'Root site Language was missing or zero.' }
                $Result = "Could not resolve tenant default SharePoint language for $TenantFilter (root site). $Detail Choose an explicit site language in the template, or ensure the tenant root site is readable."
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Warning
                throw $Result
            }
        }
    } else {
        $ResolvedLcid = 1033
    }

    switch ($TemplateName) {
        'Communication' {
            $WebTemplate = 'SITEPAGEPUBLISHING#0'
        }
        'Team' {
            $WebTemplate = 'STS#3'
        }
    }

    $WebTemplateExtensionId = '00000000-0000-0000-0000-000000000000'
    $DefaultSiteDesignIds = @( '96c933ac-3698-44c7-9f4a-5fd17d71af9e', '6142d2a0-63a5-4ba0-aede-d9fefca2c767', 'f6cc5403-0d63-442e-96c0-285923709ffc')

    switch ($SiteDesign) {
        'Topic' {
            $SiteDesignId = '96c933ac-3698-44c7-9f4a-5fd17d71af9e'
        }
        'Showcase' {
            $SiteDesignId = '6142d2a0-63a5-4ba0-aede-d9fefca2c767'
        }
        'Blank' {
            $SiteDesignId = 'f6cc5403-0d63-442e-96c0-285923709ffc'
        }
        'Custom' {
            if ($WebTemplateExtensionId -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$') {
                if ($WebTemplateExtensionId -notin $DefaultSiteDesignIds) {
                    $WebTemplateExtensionId = $SiteDesign
                    $SiteDesignId = '00000000-0000-0000-0000-000000000000'
                } else {
                    $SiteDesignId = $WebTemplateExtensionId
                }
            } else {
                $SiteDesignId = '96c933ac-3698-44c7-9f4a-5fd17d71af9e'
            }
        }
    }

    # Create the request body
    $Request = @{
        Title                  = $SiteName
        Url                    = $SiteUrl
        Lcid                   = $ResolvedLcid
        ShareByEmailEnabled    = $false
        Description            = $SiteDescription
        WebTemplate            = $WebTemplate
        SiteDesignId           = $SiteDesignId
        Owner                  = $SiteOwner
        WebTemplateExtensionId = $WebTemplateExtensionId
    }

    # Set the sensitivity label if provided
    if ($SensitivityLabel) {
        $Request.SensitivityLabel = $SensitivityLabel
    }
    if ($Classification) {
        $Request.Classification = $Classification
    }

    Write-Verbose (ConvertTo-Json -InputObject $Request -Compress -Depth 10)

    $body = @{
        request = $Request
    }

    # Create the site
    if ($PSCmdlet.ShouldProcess($SiteName, 'Create new SharePoint site')) {
        $AddedHeaders = @{
            'accept'        = 'application/json;odata.metadata=none'
            'odata-version' = '4.0'
        }
        try {
            $Results = New-GraphPOSTRequest -scope "$($SharePointInfo.AdminUrl)/.default" -uri "$($SharePointInfo.AdminUrl)/_api/SPSiteManager/create" -body (ConvertTo-Json -Depth 10 -InputObject $body) -tenantid $TenantFilter -AddedHeaders $AddedHeaders
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Result = "Failed to create new SharePoint site $SiteName with URL $SiteUrl. Error: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
            throw $Result
        }
    }

    # Check the results. This response is weird. https://learn.microsoft.com/en-us/sharepoint/dev/apis/site-creation-rest
    switch ($Results.SiteStatus) {
        '0' {
            $Result = "Failed to create new SharePoint site $SiteName with URL $SiteUrl. The site doesn't exist."
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error
            throw $Result
        }
        '1' {
            $Result = "Successfully created new SharePoint site $SiteName with URL $SiteUrl. The site is however currently being provisioned. Please wait for it to finish."
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Info
            return $Result
        }
        '2' {
            $Result = "Successfully created new SharePoint site $SiteName with URL $SiteUrl"
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Info
            return $Result
        }
        '3' {
            $Result = "Failed to create new SharePoint site $SiteName with URL $SiteUrl. An error occurred while provisioning the site."
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error
            throw $Result
        }
        '4' {
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error
            $Result = "Failed to create new SharePoint site $SiteName with URL $SiteUrl. The site already exists."
            throw $Result
        }
        default {}
    }


}

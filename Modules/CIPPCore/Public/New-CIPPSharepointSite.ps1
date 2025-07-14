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

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        $APIName = 'Create SharePoint Site',
        $Headers
    )

    $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
    $SitePath = $SiteName -replace ' ' -replace '[^A-Za-z0-9-]'
    $SiteUrl = "https://$($SharePointInfo.TenantName).sharepoint.com/sites/$SitePath"

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
        Lcid                   = 1033
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

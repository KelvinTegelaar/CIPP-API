#Region './Private/ArgumentCompleters/AssetLayoutCompleter.ps1' -1

$AssetLayoutCompleter = {
    param (
        $CommandName,
        $ParamName,
        $AssetLayout,
        $CommandAst,
        $fakeBoundParameters
    )
    if (!$script:AssetLayouts) {
        Get-HuduAssetLayouts | Out-Null
    }

    $AssetLayout = $AssetLayout -replace "'", ''
    ($script:AssetLayouts).name | Where-Object { $_ -match "$AssetLayout" } | ForEach-Object { "'$_'" }
}

Register-ArgumentCompleter -CommandName Get-HuduAssets -ParameterName AssetLayout -ScriptBlock $AssetLayoutCompleter
#EndRegion './Private/ArgumentCompleters/AssetLayoutCompleter.ps1' 18
#Region './Private/Get-HuduCompanyFolders.ps1' -1

function Get-HuduCompanyFolders {
    [CmdletBinding()]
    Param (
        [PSCustomObject]$FoldersRaw
    )

    $RootFolders = $FoldersRaw | Where-Object { $null -eq $_.parent_folder_id }
    $ReturnObject = [PSCustomObject]@{}
    foreach ($folder in $RootFolders) {
        $SubFolders = Get-HuduSubFolders -id $folder.id -FoldersRaw $FoldersRaw
        foreach ($SubFolder in $SubFolders) {
            $Folder | Add-Member -MemberType NoteProperty -Name $(Get-HuduFolderCleanName $($SubFolder.PSObject.Properties.name)) -Value $SubFolder.PSObject.Properties.value
        }
        $ReturnObject | Add-Member -MemberType NoteProperty -Name $(Get-HuduFolderCleanName $($folder.name)) -Value $folder
    }
    return $ReturnObject
}
#EndRegion './Private/Get-HuduCompanyFolders.ps1' 18
#Region './Private/Get-HuduFolderCleanName.ps1' -1

function Get-HuduFolderCleanName {
    [CmdletBinding()]
    param(
        [string]$Name
    )

    $FieldNames = @('id', 'company_id', 'icon', 'description', 'name', 'parent_folder_id', 'created_at', 'updated_at')

    if ($Name -in $FieldNames) {
        Return "fld_$Name"
    } else {
        Return $Name
    }

}
#EndRegion './Private/Get-HuduFolderCleanName.ps1' 16
#Region './Private/Get-HuduSubFolders.ps1' -1

function Get-HuduSubFolders {
    [CmdletBinding()]
    Param(
        [int]$id,
        [PSCustomObject]$FoldersRaw
    )

    $SubFolders = $FoldersRaw | Where-Object { $_.parent_folder_id -eq $id }
    $ReturnFolders = [System.Collections.ArrayList]@()
    foreach ($Folder in $SubFolders) {
        $SubSubFolders = Get-HuduSubFolders -id $Folder.id -FoldersRaw $FoldersRaw
        foreach ($AddFolder in $SubSubFolders) {
            $null = $folder | Add-Member -MemberType NoteProperty -Name $(Get-HuduFolderCleanName $($AddFolder.PSObject.Properties.name)) -Value $AddFolder.PSObject.Properties.value
        }
        $ReturnObject = [PSCustomObject]@{
            $(Get-HuduFolderCleanName $($Folder.name)) = $Folder
        }
        $null = $ReturnFolders.add($ReturnObject)
    }

    return $ReturnFolders

}
#EndRegion './Private/Get-HuduSubFolders.ps1' 24
#Region './Private/Invoke-HuduRequest.ps1' -1

function Invoke-HuduRequest {
    <#
    .SYNOPSIS
    Main Hudu API function

    .DESCRIPTION
    Calls Hudu API with token

    .PARAMETER Method
    GET,POST,DELETE,PUT,etc

    .PARAMETER Path
    Path to API endpoint

    .PARAMETER Params
    Hashtable of parameters

    .PARAMETER Body
    JSON encoded body string

    .PARAMETER Form
    Multipart form data

    .EXAMPLE
    Invoke-HuduRequest -Resource '/api/v1/articles' -Method GET
    #>
    [CmdletBinding()]
    Param(
        [Parameter()]
        [string]$Method = 'GET',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Resource,

        [Parameter()]
        [hashtable]$Params = @{},

        [Parameter()]
        [string]$Body,

        [Parameter()]
        [hashtable]$Form
    )

    $HuduAPIKey = Get-HuduApiKey
    $HuduBaseURL = Get-HuduBaseURL

    # Assemble parameters
    $ParamCollection = [System.Web.HttpUtility]::ParseQueryString([String]::Empty)

    # Sort parameters
    foreach ($Item in ($Params.GetEnumerator() | Sort-Object -CaseSensitive -Property Key)) {
        $ParamCollection.Add($Item.Key, $Item.Value)
    }

    # Query string
    $Request = $ParamCollection.ToString()

    $Headers = @{
        'x-api-key' = (New-Object PSCredential 'user', $HuduAPIKey).GetNetworkCredential().Password;
    }

    if (($Script:Int_HuduCustomHeaders | Measure-Object).count -gt 0){
        
        foreach($Entry in $Int_HuduCustomHeaders.GetEnumerator()) {
            $Headers[$Entry.Name] = $Entry.Value
        }
    }

    $ContentType = 'application/json; charset=utf-8'

    $Uri = '{0}{1}' -f $HuduBaseURL, $Resource
    # Make API call URI
    if ($Request) {
        $UriBuilder = [System.UriBuilder]$Uri
        $UriBuilder.Query = $Request
        $Uri = $UriBuilder.Uri
    }
    Write-Verbose ( '{0} [{1}]' -f $Method, $Uri )

    $RestMethod = @{
        Method      = $Method
        Uri         = $Uri
        Headers     = $Headers
        ContentType = $ContentType
    }

    if ($Body) {
        $RestMethod.Body = $Body
        Write-Verbose $Body
    }

    if ($Form) {
        $RestMethod.Form = $Form
        Write-Verbose ( $Form | Out-String )
    }

    try {
        $Results = Invoke-RestMethod @RestMethod
    } catch {
        if ("$_".trim() -eq 'Retry later' -or "$_".trim() -eq 'The remote server returned an error: (429) Too Many Requests.') {
            Write-Information 'Hudu API Rate limited. Waiting 30 Seconds then trying again'
            Start-Sleep 30
            $Results = Invoke-HuduRequest @RestMethod
        } else {
            Write-Error "'$_'"
        }
    }

    $Results
}
#EndRegion './Private/Invoke-HuduRequest.ps1' 113
#Region './Private/Invoke-HuduRequestPaginated.ps1' -1

function Invoke-HuduRequestPaginated {
    <#
    .SYNOPSIS
    Paginated requests to Hudu API

    .DESCRIPTION
    Wraps Invoke-HuduRequest with page sizes

    .PARAMETER HuduRequest
    Request to paginate

    .PARAMETER Property
    Property name to return (don't specify to return entire response object)

    .PARAMETER PageSize
    Number of results to return per page (default 1000)

    #>
    [CmdletBinding()]
    Param(
        [hashtable]$HuduRequest,
        [string]$Property,
        [int]$PageSize = 1000
    )

    $i = 1
    do {
        $HuduRequest.Params.page = $i
        $HuduRequest.Params.page_size = $PageSize
        $Response = Invoke-HuduRequest @HuduRequest
        $i++
        if ($Property) {
            $Response.$Property
        }

        else {
            $Response
        }
    } while (($Property -and $Response.$Property.count % $PageSize -eq 0 -and $Response.$Property.count -ne 0) -or (!$Property -and $Response.count % $PageSize -eq 0 -and $Response.count -ne 0))
}
#EndRegion './Private/Invoke-HuduRequestPaginated.ps1' 41
#Region './Public/Get-HuduActivityLogs.ps1' -1

function Get-HuduActivityLogs {
    <#
    .SYNOPSIS
    Get activity logs for account

    .DESCRIPTION
    Calls Hudu API to retrieve activity logs with filters

    .PARAMETER UserId
    Filter logs by user_id

    .PARAMETER UserEmail
    Filter logs by email address

    .PARAMETER ResourceId
    Filter logs by resource id. Must be coupled with resource_type

    .PARAMETER ResourceType
    Filter logs by resource type (Asset, AssetPassword, Company, Article, etc.). Must be coupled with resource_id

    .PARAMETER ActionMessage
    Filter logs by action

    .PARAMETER StartDate
    Filter logs by start date. Converts string to ISO 8601 format

    .PARAMETER EndDate
    Filter logs by end date, should be coupled with start date to limit results

    .EXAMPLE
    Get-HuduActivityLogs -StartDate 2023-02-01

    #>
    [CmdletBinding()]
    Param (
        [Alias('user_id')]
        [Int]$UserId = '',
        [Alias('user_email')]
        [String]$UserEmail = '',
        [Alias('resource_id')]
        [Int]$ResourceId = '',
        [Alias('resource_type')]
        [String]$ResourceType = '',
        [Alias('action_message')]
        [String]$ActionMessage = '',
        [Alias('start_date')]
        [DateTime]$StartDate,
        [Alias('end_date')]
        [DateTime]$EndDate
    )

    $Params = @{}

    if ($UserId) { $Params.user_id = $UserId }
    if ($UserEmail) { $Params.user_email = $UserEmail }
    if ($ResourceId) { $Params.resource_id = $ResourceId }
    if ($ResourceType) { $Params.resource_type = $ResourceType }
    if ($ActionMessage) { $Params.action_message = $ActionMessage }
    if ($StartDate) {
        $ISO8601Date = $StartDate.ToString('o');
        $Params.start_date = $ISO8601Date
    }

    $HuduRequest = @{
        Method   = 'GET'
        Resource = '/api/v1/activity_logs'
        Params   = $Params
    }

    $AllActivity = Invoke-HuduRequestPaginated -HuduRequest $HuduRequest

    if ($EndDate) {
        $AllActivity = $AllActivity | Where-Object { $([DateTime]::Parse($_.created_at)) -le $EndDate }
    }

    return $AllActivity
}
#EndRegion './Public/Get-HuduActivityLogs.ps1' 78
#Region './Public/Get-HuduApiKey.ps1' -1

function Get-HuduApiKey {
    <#
    .SYNOPSIS
    Get Hudu API key

    .DESCRIPTION
    Returns Hudu API key in securestring format

    .EXAMPLE
    Get-HuduApiKey

    #>
    [CmdletBinding()]
    Param()
    if ($null -eq $Int_HuduAPIKey) {
        Write-Error 'No API key has been set. Please use New-HuduAPIKey to set it.'
    } else {
        $Int_HuduAPIKey
    }
}
#EndRegion './Public/Get-HuduApiKey.ps1' 21
#Region './Public/Get-HuduAppInfo.ps1' -1

function Get-HuduAppInfo {
    <#
    .SYNOPSIS
    Retrieve information regarding API

    .DESCRIPTION
    Calls Hudu API to retrieve version number and date

    .EXAMPLE
    Get-HuduAppInfo

    #>
    [CmdletBinding()]
    Param()

    [version]$script:HuduRequiredVersion = '2.21'
    
    try {
        Invoke-HuduRequest -Resource '/api/v1/api_info'
    } catch {
        [PSCustomObject]@{
            version = '0.0.0.0'
            date    = '2000-01-01'
        }
    }
}
#EndRegion './Public/Get-HuduAppInfo.ps1' 27
#Region './Public/Get-HuduArticles.ps1' -1

function Get-HuduArticles {
    <#
    .SYNOPSIS
    Get Knowledge Base Articles

    .DESCRIPTION
    Calls Hudu API to retrieve KB articles by Id or a list

    .PARAMETER Id
    Id of the Article

    .PARAMETER CompanyId
    Filter by company id

    .PARAMETER Name
    Filter by name of article

    .PARAMETER Slug
    Filter by slug of article

    .EXAMPLE
    Get-HuduArticles -Name 'Article name'

    #>
    [CmdletBinding()]
    Param (
        [Int]$Id = '',
        [Alias('company_id')]
        [Int]$CompanyId = '',
        [String]$Name = '',
        [String]$Slug
    )

    if ($Id) {
        Invoke-HuduRequest -Method get -Resource "/api/v1/articles/$Id"
    } else {
        $Params = @{}

        if ($CompanyId) { $Params.company_id = $CompanyId }
        if ($Name) { $Params.name = $Name }
        if ($Slug) { $Params.slug = $Slug }

        $HuduRequest = @{
            Method   = 'GET'
            Resource = '/api/v1/articles'
            Params   = $Params
        }

        Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -Property articles
    }
}
#EndRegion './Public/Get-HuduArticles.ps1' 52
#Region './Public/Get-HuduAssetLayoutFieldID.ps1' -1

function Get-HuduAssetLayoutFieldID {
    <#
    .SYNOPSIS
    Get Hudu Asset Layout Field ID

    .DESCRIPTION
    Retrieves ID for Hudu Asset Layout Fields

    .PARAMETER Name
    Name of Field

    .PARAMETER LayoutId
    Asset Layout Id

    .EXAMPLE
    Get-HuduAssetLayoutFieldID -Name 'Extra Info' -LayoutId 1

    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [String]$Name,
        [Alias('asset_layout_id')]
        [Parameter(Mandatory = $true)]
        [Int]$LayoutId
    )

    $Layout = Get-HuduAssetLayouts -LayoutId $LayoutId

    $Fields = [Collections.Generic.List[Object]]($Layout.fields)
    $Index = $Fields.FindIndex( { $args[0].label -eq $Name } )
    $Fields[$Index].id
}
#EndRegion './Public/Get-HuduAssetLayoutFieldID.ps1' 34
#Region './Public/Get-HuduAssetLayouts.ps1' -1

function Get-HuduAssetLayouts {
    <#
    .SYNOPSIS
    Get a list of Asset Layouts

    .DESCRIPTION
    Call Hudu API to retrieve asset layouts for server

    .PARAMETER Name
    Filter by name of Asset Layout

    .PARAMETER LayoutId
    Id of Asset Layout

    .PARAMETER Slug
    Filter by url slug

    .EXAMPLE
    Get-HuduAssetLayouts -Name 'Contacts'

    #>
    [CmdletBinding()]
    Param (
        [String]$Name,
        [Alias('id', 'layout_id')]
        [int]$LayoutId,
        [String]$Slug
    )

    $HuduRequest = @{
        Resource = '/api/v1/asset_layouts'
        Method   = 'GET'
    }

    if ($LayoutId) {
        $HuduRequest.Resource = '{0}/{1}' -f $HuduRequest.Resource, $LayoutId
        $AssetLayout = Invoke-HuduRequest @HuduRequest
        return $AssetLayout.asset_layout
    } else {
        $Params = @{}
        if ($Name) { $Params.name = $Name }
        if ($Slug) { $Params.slug = $Slug }
        $HuduRequest.Params = $Params

        $AssetLayouts = Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -Property 'asset_layouts' -PageSize 25

        if (!$Name -and !$Slug) {
            $script:AssetLayouts = $AssetLayouts | Sort-Object -Property name
        }
        $AssetLayouts
    }
}
#EndRegion './Public/Get-HuduAssetLayouts.ps1' 53
#Region './Public/Get-HuduAssets.ps1' -1

function Get-HuduAssets {
    <#
    .SYNOPSIS
    Get a list of Assets

    .DESCRIPTION
    Call Hudu API to retrieve Assets

    .PARAMETER Id
    Id of requested asset

    .PARAMETER AssetLayoutId
    Id of the requested asset layout

    .PARAMETER AssetLayout
    Name of the requested asset layout

    .PARAMETER CompanyId
    Id of the requested company

    .PARAMETER Name
    Filter by name

    .PARAMETER Archived
    Show archived results

    .PARAMETER PrimarySerial
    Filter by primary serial

    .PARAMETER Slug
    Filter by slug

    .EXAMPLE
    Get-HuduAssets -AssetLayout 'Contacts'

    #>
    [CmdletBinding()]
    Param (
        [ValidateRange(1, [int]::MaxValue)]
        [Int]$Id = '',
        [Alias('asset_layout_id')]
        [ValidateRange(1, [int]::MaxValue)]
        [Int]$AssetLayoutId = '',
        [string]$AssetLayout,
        [Alias('company_id')]
        [ValidateRange(1, [int]::MaxValue)]
        [Int]$CompanyId = '',
        [String]$Name = '',
        [switch]$Archived,
        [Alias('primary_serial')]
        [String]$PrimarySerial = '',
        [String]$Slug
    )

    if ($AssetLayout) {
        if (!$script:AssetLayouts) { Get-HuduAssetLayouts | Out-Null }
        $AssetLayoutId = $script:AssetLayouts | Where-Object { $_.name -eq $AssetLayout } | Select-Object -ExpandProperty id
    }

    if ($id -and $CompanyId) {
        $HuduRequest = @{
            Resource = "/api/v1/companies/$CompanyId/assets/$Id"
            Method   = 'GET'
        }
        Invoke-HuduRequest @HuduRequest
    } else {
        $Params = @{}
        if ($CompanyId) { $Params.company_id = $CompanyId }
        if ($AssetLayoutId) { $Params.asset_layout_id = $AssetLayoutId }
        if ($Name) { $Params.name = $Name }
        if ($Archived.IsPresent) { $params.archived = $Archived.IsPresent }
        if ($PrimarySerial) { $Params.primary_serial = $PrimarySerial }
        if ($Id) { $Params.id = $Id }
        if ($Slug) { $Params.slug = $Slug }

        $HuduRequest = @{
            Resource = '/api/v1/assets'
            Method   = 'GET'
            Params   = $Params
        }
        Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -Property assets
    }
}
#EndRegion './Public/Get-HuduAssets.ps1' 84
#Region './Public/Get-HuduBaseURL.ps1' -1

function Get-HuduBaseURL {
    <#
    .SYNOPSIS
    Get Hudu Base URL

    .DESCRIPTION
    Returns Hudu Base URL

    .EXAMPLE
    Get-HuduBaseURL

    #>
    [CmdletBinding()]
    Param()
    if ($null -eq $Int_HuduBaseURL) {
        Write-Error 'No Base URL has been set. Please use New-HuduBaseURL to set it.'
    } else {
        $Int_HuduBaseURL
    }
}
#EndRegion './Public/Get-HuduBaseURL.ps1' 21
#Region './Public/Get-HuduCard.ps1' -1

function Get-HuduCard {
    <#
    .SYNOPSIS
    Get Integration Cards

    .DESCRIPTION
    Lookup cards with outside integration details

    .PARAMETER IntegrationSlug
    Identifier of outside integration

    .PARAMETER IntegrationId
    ID in the integration. Must be present, unless integration_identifier is set

    .PARAMETER IntegrationIdentifier
    Identifier in the integration (if integration_id is not set)

    .EXAMPLE
    Get-HuduCard -IntegrationSlug cw_manage -IntegrationId 1

    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [Alias('integration_slug')]
        [String]$IntegrationSlug,

        [Alias('integration_id')]
        [String]$IntegrationId,

        [Alias('integration_identifier')]
        [String]$IntegrationIdentifier
    )

    $Params = @{
        integration_slug = $IntegrationSlug
    }

    if ($IntegrationId) { $Params.integration_id = $IntegrationId }
    if ($IntegrationIdentifier) { $Params.integration_identifier = $IntegrationIdentifier }

    if (!$IntegrationId -and !$IntegrationIdentifier) {
        throw 'IntegrationId or IntegrationIdentifier required'
    }

    $HuduRequest = @{
        Method   = 'GET'
        Resource = '/api/v1/cards/lookup'
        Params   = $Params
    }

    Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -Property integrator_cards
}
#EndRegion './Public/Get-HuduCard.ps1' 54
#Region './Public/Get-HuduCompanies.ps1' -1

function Get-HuduCompanies {
    <#
    .SYNOPSIS
    Get a list of companies

    .DESCRIPTION
    Call Hudu API to retrieve company list

    .PARAMETER Id
    Filter companies by id

    .PARAMETER Name
    Filter companies by name

    .PARAMETER PhoneNumber
    filter companies by phone number

    .PARAMETER Website
    Filter companies by website

    .PARAMETER City
    Filter companies by city

    .PARAMETER State
    Filter companies by state

    .PARAMETER Search
    Filter by search query

    .PARAMETER Slug
    Filter by url slug

    .PARAMETER IdInIntegration
    Filter companies by id/identifier in PSA/RMM/outside integration

    .EXAMPLE
    Get-HuduCompanies -Search 'Vendor'

    #>
    [CmdletBinding()]
    Param (
        [String]$Name = '',
        [Alias('phone_number')]
        [String]$PhoneNumber = '',
        [String]$Website = '',
        [String]$City = '',
        [String]$State = '',
        [Alias('id_in_integration')]
        [Int]$IdInIntegration = '',
        [Int]$Id = '',
        [string]$Search,
        [String]$Slug
    )

    if ($Id) {
        $Company = (Invoke-HuduRequest -Method get -Resource "/api/v1/companies/$Id").company
        return $Company
    } else {
        $Params = @{}
        if ($Name) { $Params.name = $Name }
        if ($PhoneNumber) { $Params.phone_number = $PhoneNumber }
        if ($Website) { $Params.website = $Website }
        if ($City) { $Params.city = $City }
        if ($State) { $Params.state = $State }
        if ($IdInIntegration) { $Params.id_in_integration = $IdInIntegration }
        if ($Search) { $Params.search = $Search }
        if ($Slug) { $Params.slug = $Slug }

        $HuduRequest = @{
            Method   = 'GET'
            Resource = '/api/v1/companies'
            Params   = $Params
        }

        Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -Property 'companies'
    }
}
#EndRegion './Public/Get-HuduCompanies.ps1' 78
#Region './Public/Get-HuduExpirations.ps1' -1

function Get-HuduExpirations {
    <#
    .SYNOPSIS
    Get expirations for account

    .DESCRIPTION
    Calls Hudu API to retrieve expirations

    .PARAMETER CompanyId
    Filter expirations by company_id

    .PARAMETER ExpirationType
    Filter expirations by expiration type (undeclared, domain, ssl_certificate, warranty, asset_field, article_expiration)

    .PARAMETER ResourceId
    Filter logs by resource id. Must be coupled with resource_type

    .PARAMETER ResourceType
    Filter logs by resource type (Asset, AssetPassword, Company, Article, etc.). Must be coupled with resource_id

    .EXAMPLE
    Get-HuduExpirations -ExpirationType domain

    #>
    [CmdletBinding()]
    Param (
        [Alias('company_id')]
        [Int]$CompanyId = '',

        [ValidateSet('undeclared', 'domain', 'ssl_certificate', 'warranty', 'asset_field', 'article_expiration')]
        [Alias('expiration_type')]
        [String]$ExpirationType = '',

        [Alias('resource_id')]
        [Int]$ResourceId = '',

        [Alias('resource_type')]
        [String]$ResourceType = ''
    )

    $Params = @{}

    if ($CompanyId) { $Params.company_id = $CompanyId }
    if ($ExpirationType) { $Params.expiration_type = $ExpirationType }
    if ($ResourceType) { $Params.resource_type = $ResourceType }
    if ($ResourceId) { $Params.resource_id = $ResourceId }

    $HuduRequest = @{
        Method   = 'GET'
        Resource = '/api/v1/expirations'
        Params   = $Params
    }

    Invoke-HuduRequestPaginated -HuduRequest $HuduRequest
}
#EndRegion './Public/Get-HuduExpirations.ps1' 56
#Region './Public/Get-HuduFolderMap.ps1' -1

function Get-HuduFolderMap {
    [CmdletBinding()]
    Param (
        [Alias('company_id')]
        [Int]$CompanyId = ''
    )

    if ($CompanyId) {
        $FoldersRaw = Get-HuduFolders -company_id $CompanyId
        $SubFolders = Get-HuduCompanyFolders -FoldersRaw $FoldersRaw
    } else {
        $FoldersRaw = Get-HuduFolders
        $FoldersProcessed = $FoldersRaw | Where-Object { $null -eq $_.company_id }
        $SubFolders = Get-HuduCompanyFolders -FoldersRaw $FoldersProcessed
    }

    return $SubFolders
}
#EndRegion './Public/Get-HuduFolderMap.ps1' 19
#Region './Public/Get-HuduFolders.ps1' -1

function Get-HuduFolders {
    <#
    .SYNOPSIS
    Get a list of Folders

    .DESCRIPTION
    Calls Hudu API to retrieve folders

    .PARAMETER Id
    Id of the folder

    .PARAMETER Name
    Filter by name

    .PARAMETER CompanyId
    Filter by company_id

    .EXAMPLE
    Get-HuduFolders

    #>
    [CmdletBinding()]
    Param (
        [Int]$Id = '',
        [String]$Name = '',
        [Alias('company_id')]
        [Int]$CompanyId = ''
    )

    if ($id) {
        $Folder = Invoke-HuduRequest -Method get -Resource "/api/v1/folders/$id"
        return $Folder.Folder
    } else {
        $Params = @{}

        if ($CompanyId) { $Params.company_id = $CompanyId }
        if ($Name) { $Params.name = $Name }

        $HuduRequest = @{
            Method   = 'GET'
            Resource = '/api/v1/folders'
            Params   = $Params
        }
        Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -Property folders
    }
}
#EndRegion './Public/Get-HuduFolders.ps1' 47
#Region './Public/Get-HuduIntegrationMatchers.ps1' -1

function Get-HuduIntegrationMatchers {
    <#
    .SYNOPSIS
    List matchers for an integration

    .DESCRIPTION
    Calls Hudu API to get list of integration matching

    .PARAMETER IntegrationId
    ID of the integration. Can be found in the URL when editing an integration

    .PARAMETER Matched
    Filter on whether the company already been matched

    .PARAMETER SyncId
    Filter by ID of the record in the integration. This is used if the id that the integration uses is an integer.

    .PARAMETER Identifier
    Filter by Identifier in the integration (if sync_id is not set). This is used if the id that the integration uses is a string.

    .PARAMETER CompanyId
    Filter on company id

    .EXAMPLE
    Get-HuduIntegrationMatchers -IntegrationId 1

    #>
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [int]$IntegrationId,

        [switch]$Matched,

        [int]$SyncId = '',

        [string]$Identifier = '',

        [int]$CompanyId
    )

    $Params = @{
        integration_id = $IntegrationId
    }

    if ($Matched.IsPresent) { $Params.matched = 'true' }
    if ($CompanyId) { $Params.company_id = $CompanyId }
    if ($Identifier) { $Params.identifier = $Identifier }
    if ($SyncId) { $Params.sync_id = $SyncId }

    $HuduRequest = @{
        Method   = 'GET'
        Resource = '/api/v1/matchers'
        Params   = $Params
    }
    Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -Property 'matchers'
}
#EndRegion './Public/Get-HuduIntegrationMatchers.ps1' 58
#Region './Public/Get-HuduMagicDashes.ps1' -1

function Get-HuduMagicDashes {
    <#
    .SYNOPSIS
    Get all Magic Dash Items

    .DESCRIPTION
    Call Hudu API to retrieve Magic Dashes

    .PARAMETER CompanyId
    Filter by company id

    .PARAMETER Title
    Filter by title

    .EXAMPLE
    Get-HuduMagicDashes -Title 'Microsoft 365 - ...'

    #>
    Param (
        [Alias('company_id')]
        [Int]$CompanyId,
        [String]$Title
    )

    $Params = @{}

    if ($CompanyId) { $Params.company_id = $CompanyId }
    if ($Title) { $Params.title = $Title }

    $HuduRequest = @{
        Method   = 'GET'
        Resource = '/api/v1/magic_dash'
        Params   = $Params
    }
    Invoke-HuduRequestPaginated -HuduRequest $HuduRequest
}
#EndRegion './Public/Get-HuduMagicDashes.ps1' 37
#Region './Public/Get-HuduObjectByUrl.ps1' -1

function Get-HuduObjectByUrl {
    <#
    .SYNOPSIS
    Get Hudu object from URL

    .DESCRIPTION
    Calls Hudu API to retrieve object based on URL string

    .PARAMETER Url
    Url to retrieve object from

    .EXAMPLE
    Get-HuduObject -Url https://your-hudu-server/a/some-asset-1z8z7a

    #>
    [CmdletBinding()]
    Param (
        [uri]$Url
    )

    if ((Get-HuduBaseURL) -match $Url.Authority) {
        $null, $Type, $Slug = $Url.PathAndQuery -split '/'

        $SlugSplat = @{
            Slug = $Slug
        }

        switch ($Type) {
            'a' {
                # Asset
                Get-HuduAssets @SlugSplat
            }
            'admin' {
                # Admin path
                $null, $null, $Type, $Slug = $Url.PathAndQuery -split '/'
                $SlugSplat = @{
                    Slug = $Slug
                }
                switch ($Type) {
                    'asset_layouts' {
                        # Asset layouts
                        Get-HuduAssetLayouts @SlugSplat
                    }
                }
            }
            'c' {
                # Company
                Get-HuduCompanies @SlugSplat
            }
            'kba' {
                # KB article
                Get-HuduArticles @SlugSplat
            }
            'passwords' {
                # Passwords
                Get-HuduPasswords @SlugSplat
            }
            'websites' {
                # Website
                Get-HuduWebsites @SlugSplat
            }
            default {
                Write-Error "Unsupported object type $Type"
            }
        }
    } else {
        Write-Error 'Provided URL does not match Hudu Base URL'
    }
}
#EndRegion './Public/Get-HuduObjectByUrl.ps1' 70
#Region './Public/Get-HuduPasswordFolders.ps1' -1

function Get-HuduPasswordFolders {
    <#
    .SYNOPSIS
    Get a list of Password Folders

    .DESCRIPTION
    Calls Hudu API to retrieve folders

    .PARAMETER Id
    Id of the folder

    .PARAMETER Name
    Filter by name

    .PARAMETER CompanyId
    Filter by company_id

    .EXAMPLE
    Get-HuduFolders

    #>
    [CmdletBinding()]
    Param (
        [Int]$Id = '',
        [String]$Name = '',
        [String]$Search = '',
        [Alias('company_id')]
        [Int]$CompanyId = '',
        [Int]$page = '',
        [Int]$page_size = ''
    )

    if ($id) {
        $Folder = Invoke-HuduRequest -Method get -Resource "/api/v1/password_folders/$id"
        return $Folder.password_folder
    } else {
        $Params = @{}

        if ($CompanyId) { $Params.company_id = $CompanyId }
        if ($Name) { $Params.name = $Name }

        $HuduRequest = @{
            Method   = 'GET'
            Resource = '/api/v1/password_folders'
            Params   = $Params
        }
        Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -Property password_folders
    }
}
#EndRegion './Public/Get-HuduPasswordFolders.ps1' 50
#Region './Public/Get-HuduPasswords.ps1' -1

function Get-HuduPasswords {
    <#
    .SYNOPSIS
    Get a list of Passwords

    .DESCRIPTION
    Calls Hudu API to list password assets

    .PARAMETER Id
    Id of the password

    .PARAMETER CompanyId
    Filter by company id

    .PARAMETER Name
    Filter by password name

    .PARAMETER Slug
    Filter by url slug

    .PARAMETER Search
    Filter by search query

    .EXAMPLE
    Get-HuduPasswords -CompanyId 1

    #>
    [CmdletBinding()]
    Param (
        [Int]$Id,

        [Alias('company_id')]
        [Int]$CompanyId,

        [String]$Name,

        [String]$Slug,

        [string]$Search
    )

    if ($Id) {
        $Password = Invoke-HuduRequest -Method get -Resource "/api/v1/asset_passwords/$id"
        return $Password
    } else {
        $Params = @{}
        if ($CompanyId) { $Params.company_id = $CompanyId }
        if ($Name) { $Params.name = $Name }
        if ($Slug) { $Params.slug = $Slug }
        if ($Search) { $Params.search = $Search }
    }

    $HuduRequest = @{
        Method   = 'GET'
        Resource = '/api/v1/asset_passwords'
        Params   = $Params
    }
    Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -Property 'asset_passwords'
}
#EndRegion './Public/Get-HuduPasswords.ps1' 60
#Region './Public/Get-HuduProcesses.ps1' -1

function Get-HuduProcesses {
    <#
    .SYNOPSIS
    Get a list of Procedures (Processes)

    .DESCRIPTION
    Calls Hudu API to retrieve list of procedures

    .PARAMETER Id
    Id of the Procedure

    .PARAMETER CompanyId
    Filter by company id

    .PARAMETER Name
    Fitler by name of article

    .PARAMETER Slug
    Filter by url slug

    .EXAMPLE
    Get-HuduProcedures -Name 'Procedure 1'

    #>
    [CmdletBinding()]
    Param (
        [Int]$Id = '',
        [Alias('company_id')]
        [Int]$CompanyId = '',
        [String]$Name = '',
        [String]$Slug
    )

    if ($Id) {
        Invoke-HuduRequest -Method get -Resource "/api/v1/procedures/$id"
    } else {
        $Params = @{}

        if ($CompanyId) { $Params.company_id = $CompanyId }
        if ($Name) { $Params.name = $Name }
        if ($Slug) { $Params.slug = $Slug }


        $HuduRequest = @{
            Method   = 'GET'
            Resource = '/api/v1/procedures'
            Params   = $Params
        }
        Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -Property 'procedures'
    }
}
#EndRegion './Public/Get-HuduProcesses.ps1' 52
#Region './Public/Get-HuduPublicPhotos.ps1' -1

function Get-HuduPublicPhotos {
    <#
    .SYNOPSIS
    Get a list of Public_Photos

    .DESCRIPTION
    Calls Hudu API to retrieve public photos

    .EXAMPLE
    Get-HuduPublicPhotos

    #>
    [CmdletBinding()]
    Param()

    $HuduRequest = @{
        Method   = 'GET'
        Resource = '/api/v1/public_photos'
        Params   = @{}
    }
    Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -Property 'public_photos'
}
#EndRegion './Public/Get-HuduPublicPhotos.ps1' 23
#Region './Public/Get-HuduRelations.ps1' -1

function Get-HuduRelations {
    <#
    .SYNOPSIS
    Get a list of all relations

    .DESCRIPTION
    Calls Hudu API to retrieve object relationsihps

    .EXAMPLE
    Get-HuduRelations -CompanyId 1

    #>
    [CmdletBinding()]
    Param()

    $HuduRequest = @{
        Method   = 'GET'
        Resource = '/api/v1/relations'
        Params   = @{}
    }

    Invoke-HuduRequestPaginated -HuduRequest $HuduRequest -Property 'relations'
}
#EndRegion './Public/Get-HuduRelations.ps1' 24
#Region './Public/Get-HuduUploads.ps1' -1

function Get-HuduUploads {
    <#
    .SYNOPSIS
    Get a list of uploads

    .DESCRIPTION
    Calls Hudu API to retrieve uploads

    .EXAMPLE
    Get-HuduUploads

    #>
    [CmdletBinding()]
    Param(
        [Int]$Id
    )

    if ($Id) {
        $Upload = Invoke-HuduRequest -Method Get -Resource "/api/v1/uploads/$Id"
    } else {
        $Upload = Invoke-HuduRequest -Method Get -Resource "/api/v1/uploads"
    }
    return $Upload
}
#EndRegion './Public/Get-HuduUploads.ps1' 25
#Region './Public/Get-HuduWebsites.ps1' -1

function Get-HuduWebsites {
    <#
	.SYNOPSIS
	Get a list of all websites

	.DESCRIPTION
	Calls Hudu API to get websites

	.PARAMETER Name
	Filter websites by name

	.PARAMETER Id
	ID of website

	.PARAMETER Slug
	Filter by url slug

    .PARAMETER Search
    Fitler by search query

	.EXAMPLE
	Get-HuduWebsites -Search 'domain.com'

	#>
    [CmdletBinding()]
    Param (
        [String]$Name,
        [Alias('website_id')]
        [Int]$WebsiteId,
        [String]$Slug,
        [string]$Search
    )

    if ($WebsiteId) {
        Invoke-HuduRequest -Method get -Resource "/api/v1/websites/$($WebsiteId)"
    } else {
        $Params = @{}
        if ($Name) { $Params.name = $Name }
        if ($Slug) { $Params.slug = $Slug }
        if ($Search) { $Params.search = $Search }

        $HuduRequest = @{
            Method   = 'GET'
            Resource = '/api/v1/websites'
            Params   = $Params
        }
        Invoke-HuduRequestPaginated -HuduRequest $HuduRequest
    }
}
#EndRegion './Public/Get-HuduWebsites.ps1' 50
#Region './Public/Initialize-HuduFolder.ps1' -1

function Initialize-HuduFolder {
    [CmdletBinding()]
    param(
        [String[]]$FolderPath,
        [Alias('company_id')]
        [int]$CompanyId
    )

    if ($CompanyId) {
        $FolderMap = Get-HuduFolderMap -company_id $CompanyId
    } else {
        $FolderMap = Get-HuduFolderMap
    }

    $CurrentFolder = $Foldermap
    foreach ($Folder in $FolderPath) {
        if ($CurrentFolder.$(Get-HuduFolderCleanName $Folder)) {
            $CurrentFolder = $CurrentFolder.$(Get-HuduFolderCleanName $Folder)
        } else {
            $CurrentFolder = (New-HuduFolder -Name $Folder -company_id $CompanyID -parent_folder_id $CurrentFolder.id).folder
        }
    }

    return $CurrentFolder
}
#EndRegion './Public/Initialize-HuduFolder.ps1' 26
#Region './Public/Move-HuduAssetsToNewLayout.ps1' -1

function Move-HuduAssetsToNewLayout {
<#
    .SYNOPSIS
    Helper function that uses the Set-HuduAsset function to move an asset between asset layouts. This will leave behind orphan data in the database.
    Review the article https://portal.risingtidegroup.net/kb?id=29 for more details.

    .DESCRIPTION
    Calls the Hudu API to update an asset by switching its asset_layout_id property to a different asset layout. 
    This function migrates the asset to the specified new layout while maintaining its fields. Note that this 
    operation may leave behind orphaned data in the Hudu database, so use it with caution.

    .PARAMETER AssetsToMove
    An array of assets to be moved to a new asset layout. Each asset must contain both 'id' and 'fields' properties.

    .PARAMETER NewAssetLayoutID
    The ID of the new asset layout to which the assets will be moved.

    .EXAMPLE
    $AssetLayout = Get-HuduAssetLayouts -Name "Servers"
    $AssetsToUpdate = Get-HuduAssets -AssetLayoutId 9
    Move-HuduAssetsToNewLayout -AssetsToMove $AssetsToUpdate -NewAssetLayoutID $AssetLayout.id

    This example retrieves the asset layout with the name "Servers" and the assets with the layout ID 9, then moves those assets to the new layout.

    .NOTES
    Ensure that the new asset layout ID is valid and that the assets to be moved contain the required properties.
    Using this function may result in orphaned data in your Hudu database. Review the provided article for more details.
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                if ($BadAssets = ($_ | where {(-not $_.id)})) {
                    $BadAssets
                    throw "Assets must be an object with an ID"
                }
            return $true
        })]
        [array]
        $AssetsToMove,

        [Parameter(Mandatory = $true)]
        [int]
        $NewAssetLayoutID
    )

    Write-Warning "Performing this function will leave behind orphaned data in your Hudu database. Please review https://portal.risingtidegroup.net/kb?id=29"
    Read-Host "Press Enter to continue or (CTRL+C) to cancel..."

    $assets = foreach ($AssetToMove in $AssetsToMove) {
        if (-not ($AssetToMove.PSObject.Properties.Match('id')) -or -not ($AssetToMove.PSObject.Properties.Match('fields'))) {
            Write-Error "Asset does not contain both 'id' and 'fields' properties. Skipping this asset."
            continue
        }

        if (-not $AssetToMove.fields) {
            Write-Warning "Asset ID: $($AssetToMove.id) has no fields. Proceeding with moving the asset."
        }

        $assetId = $AssetToMove.id

        if ($PSCmdlet.ShouldProcess("Asset ID: $assetId", "Move to new layout with ID $NewAssetLayoutID")) {
            try {
                Write-Verbose "Processing Asset ID: $assetId"

                $fields = New-Object -TypeName psobject
                foreach ($field in $AssetToMove.fields) {
                    $fieldName = $field.label.replace(' ', '_').tolower()
                    $fields | Add-Member -MemberType NoteProperty -Name $fieldName -Value $field.value -Force
                }

                (Set-HuduAsset -Id $assetId -AssetLayoutId $NewAssetLayoutID -Fields $fields).asset

                Write-Verbose "Successfully moved Asset ID: $assetId"
            }
            catch {
                Write-Error "Failed to move Asset ID: $assetId. Error: $_"
            }
            finally {
                Remove-Variable -Name fields -ErrorAction SilentlyContinue
            }
        }
    }
    return $assets
}
#EndRegion './Public/Move-HuduAssetsToNewLayout.ps1' 87
#Region './Public/New-HuduAPIKey.ps1' -1

function New-HuduAPIKey {
    <#
    .SYNOPSIS
    Set Hudu API Key

    .DESCRIPTION
    API keys are required to interact with Hudu

    .PARAMETER ApiKey
    The API key

    .EXAMPLE
    New-HuduAPIKey -ApiKey abdc1234

    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Scope = 'Function')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Scope = 'Function')]
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [String]$ApiKey
    )

    process {
        if ($ApiKey) {
            $SecApiKey = ConvertTo-SecureString $ApiKey -AsPlainText -Force
        } else {
            $SecApiKey = Read-Host -Prompt 'Please enter your Hudu API key, you can obtain it from https://your-hudu-domain/admin/api_keys:' -AsSecureString
        }
        Set-Variable -Name 'Int_HuduAPIKey' -Value $SecApiKey -Visibility Private -Scope script -Force

        if ($script:Int_HuduBaseURL) {
            [version]$version = (Get-HuduAppInfo).version
            if ($version -lt $script:HuduRequiredVersion) {
                Write-Warning "A connection error occured or Hudu version is below $script:HuduRequiredVersion"
            }
        }
    }
}
#EndRegion './Public/New-HuduAPIKey.ps1' 40
#Region './Public/New-HuduArticle.ps1' -1

function New-HuduArticle {
    <#
    .SYNOPSIS
    Create a Knowledge Base Article

    .DESCRIPTION
    Uses Hudu API to create KB articles

    .PARAMETER Name
    Name of article

    .PARAMETER Content
    Article HTML contents

    .PARAMETER EnableSharing
    Create public URL for users to view without being authenticated

    .PARAMETER FolderId
    Associate article with folder id

    .PARAMETER CompanyId
    Associate article with company id

    .PARAMETER Slug
    Manually define slug for Article

    .EXAMPLE
    New-HuduArticle -Name "Test" -CompanyId 1 -Content '<h1>Testing</h1>' -EnableSharing -Slug 'this-is-a-test'

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [String]$Name,

        [Parameter(Mandatory = $true)]
        [String]$Content,

        [switch]$EnableSharing,

        [Alias('folder_id')]
        [Int]$FolderId = '',

        [Alias('company_id')]
        [Int]$CompanyId = '',

        [string]$Slug
    )

    $Article = [ordered]@{article = [ordered]@{} }

    $Article.article.add('name', $Name)
    $Article.article.add('content', $Content)

    if ($FolderId) {
        $Article.article.add('folder_id', $FolderId)
    }

    if ($CompanyId) {
        $Article.article.add('company_id', $CompanyId)
    }

    if ($EnableSharing.IsPresent) {
        $Article.article.add('enable_sharing', 'true')
    }

    if ($Slug) {
        $Article.article.add('slug', $Slug)
    }

    $JSON = $Article | ConvertTo-Json -Depth 10

    if ($PSCmdlet.ShouldProcess($Name)) {
        Invoke-HuduRequest -Method post -Resource '/api/v1/articles' -Body $JSON
    }
}
#EndRegion './Public/New-HuduArticle.ps1' 77
#Region './Public/New-HuduAsset.ps1' -1

function New-HuduAsset {
    <#
    .SYNOPSIS
    Create an Asset

    .DESCRIPTION
    Uses Hudu API to create assets using custom layouts

    .PARAMETER Name
    Name of the Asset

    .PARAMETER CompanyId
    Company id for asset

    .PARAMETER AssetLayoutId
    Asset layout id

    .PARAMETER Fields
    Array of custom fields and values

    .PARAMETER PrimarySerial
    Asset primary serial number

    .PARAMETER PrimaryMail
    Asset primary mail

    .PARAMETER PrimaryModel
    Asset primary model

    .PARAMETER PrimaryManufacturer
    Asset primary manufacturer

    .PARAMETER Slug
    Url identifier

    .EXAMPLE
    New-HuduAsset -Name 'Some asset' -CompanyId 1 -Fields @(@{'field_name'='Field Value'})

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [String]$Name,

        [Alias('company_id')]
        [Parameter(Mandatory = $true)]
        [Int]$CompanyId,

        [Alias('asset_layout_id')]
        [Parameter(Mandatory = $true)]
        [Int]$AssetLayoutId,

        [Array]$Fields,

        [Alias('primary_serial')]
        [string]$PrimarySerial,

        [Alias('primary_mail')]
        [string]$PrimaryMail,

        [Alias('primary_model')]
        [string]$PrimaryModel,

        [Alias('primary_manufacturer')]
        [string]$PrimaryManufacturer
    )

    $Asset = [ordered]@{asset = [ordered]@{} }

    $Asset.asset.add('name', $Name)
    $Asset.asset.add('asset_layout_id', $AssetLayoutId)


    if ($PrimarySerial) {
        $Asset.asset.add('primary_serial', $PrimarySerial)
    }

    if ($PrimaryMail) {
        $Asset.asset.add('primary_mail', $PrimaryMail)
    }

    if ($PrimaryModel) {
        $Asset.asset.add('primary_model', $PrimaryModel)
    }

    if ($PrimaryManufacturer) {
        $Asset.asset.add('primary_manufacturer', $PrimaryManufacturer)
    }

    if ($Fields) {
        $Asset.asset.add('custom_fields', $Fields)
    }

    if ($Slug) {
        $Asset.asset.add('slug', $Slug)
    }

    $JSON = $Asset | ConvertTo-Json -Depth 10

    if ($PSCmdlet.ShouldProcess($Name)) {
        Invoke-HuduRequest -Method post -Resource "/api/v1/companies/$CompanyId/assets" -Body $JSON
    }
}
#EndRegion './Public/New-HuduAsset.ps1' 104
#Region './Public/New-HuduAssetLayout.ps1' -1

function New-HuduAssetLayout {
    <#
    .SYNOPSIS
    Create an Asset Layout

    .DESCRIPTION
    Uses Hudu API to create new custom asset layout

    .PARAMETER Name
    Name of the layout

    .PARAMETER Icon
    FontAwesome Icon class name, example: "fas fa-home"

    .PARAMETER Color
    Background color hex code

    .PARAMETER IconColor
    Icon color hex code

    .PARAMETER IncludePasswords
    Boolean for including passwords

    .PARAMETER IncludePhotos
    Boolean for including photos

    .PARAMETER IncludeComments
    Boolean for including comments

    .PARAMETER IncludeFiles
    Boolean for including files

    .PARAMETER PasswordTypes
    List of password types, separated with new line characters

    .PARAMETER Slug
    Url identifier

    .PARAMETER Fields
    Array of hashtable or custom objects representing layout fields. Most field types only require a label and type.
    Valid field types are: Text, RichText, Heading, CheckBox, Website (aka Link), Password (aka ConfidentialText), Number, Date, DropDown, Embed, Email (aka CopyableText), Phone, AssetLink
    Field types are Case Sensitive as of Hudu V2.27 due to a known issue with asset type validation.

    .EXAMPLE
    New-HuduAssetLayout -Name 'Test asset layout' -Icon 'fas fa-home' -IncludePassword $true

    .EXAMPLE
    New-HuduAssetLayout -Name 'Test asset layout' -Icon 'fas fa-home' -IncludePassword $true -Fields @(
        @{label = 'Test field'; 'field_type' = 'Text'}
    )
    #>
    [CmdletBinding(SupportsShouldProcess)]
    # This will silence the warning for variables with Password in their name.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '')]
    Param (
        [Parameter(Mandatory = $true)]
        [String]$Name,

        [Parameter(Mandatory = $true)]
        [String]$Icon,

        [Parameter(Mandatory = $true)]
        [String]$Color,

        [Alias('icon_color')]
        [Parameter(Mandatory = $true)]
        [String]$IconColor,

        [Alias('include_passwords')]
        [bool]$IncludePasswords = '',

        [Alias('include_photos')]
        [bool]$IncludePhotos = '',

        [Alias('include_comments')]
        [bool]$IncludeComments = '',

        [Alias('include_files')]
        [bool]$IncludeFiles = '',

        [Alias('password_types')]
        [String]$PasswordTypes = '',

        [Parameter(Mandatory = $true)]
        [system.collections.generic.list[hashtable]]$Fields
    )

    foreach ($field in $fields) {
        if ($field.show_in_list) { $field.show_in_list = [System.Convert]::ToBoolean($field.show_in_list) } else { $field.remove('show_in_list') }
        if ($field.required) { $field.required = [System.Convert]::ToBoolean($field.required) } else { $field.remove('required') }
        if ($field.expiration) { $field.expiration = [System.Convert]::ToBoolean($field.expiration) } else { $field.remove('expiration') }
        # A bug in versions of Hudu 2.27 and earlier can cause asset layouts to become corrupted if the field type value is not properly cased.
        switch ($field.'field_type') {
            'text'              { $field.'field_type' = 'Text' }
            'richtext'          { $field.'field_type' = 'RichText' }
            'heading'           { $field.'field_type' = 'Heading' }
            'checkbox'          { $field.'field_type' = 'CheckBox' }
            'number'            { $field.'field_type' = 'Number' }
            'date'              { $field.'field_type' = 'Date' }
            'dropdown'          { $field.'field_type' = 'Dropdown' }
            'embed'             { $field.'field_type' = 'Embed' }
            'phone'             { $field.'field_type' = 'Phone' }
            'email'             { $field.'field_type' = 'Email' }
            'copyabletext'      { $field.'field_type' = 'Email' }
            'assettag'          { $field.'field_type' = 'AssetTag' }
            'assetlink'         { $field.'field_type' = 'AssetTag' }
            'website'           { $field.'field_type' = 'Website' }
            'link'              { $field.'field_type' = 'Website' }
            'password'          { $field.'field_type' = 'Password' }
            'confidentialtext'  { $field.'field_type' = 'Password' }
            Default { throw "Invalid field type: $($field.'field_type') found in field $($field.name)" }
        }
    }

    $AssetLayout = [ordered]@{asset_layout = [ordered]@{} }

    $AssetLayout.asset_layout.add('name', $Name)
    $AssetLayout.asset_layout.add('icon', $Icon)
    $AssetLayout.asset_layout.add('color', $Color)
    $AssetLayout.asset_layout.add('icon_color', $IconColor)
    $AssetLayout.asset_layout.add('fields', $Fields)
    #$AssetLayout.asset_layout.add('active', $Active)

    if ($IncludePasswords) {
        $AssetLayout.asset_layout.add('include_passwords', [System.Convert]::ToBoolean($IncludePasswords))
    }

    if ($IncludePhotos) {
        $AssetLayout.asset_layout.add('include_photos', [System.Convert]::ToBoolean($IncludePhotos))
    }

    if ($IncludeComments) {
        $AssetLayout.asset_layout.add('include_comments', [System.Convert]::ToBoolean($IncludeComments))
    }

    if ($IncludeFiles) {
        $AssetLayout.asset_layout.add('include_files', [System.Convert]::ToBoolean($IncludeFiles))
    }

    if ($PasswordTypes) {
        $AssetLayout.asset_layout.add('password_types', $PasswordTypes)
    }

    if ($Slug) {
        $AssetLayout.asset_layout.add('slug', $Slug)
    }

    $JSON = $AssetLayout | ConvertTo-Json -Depth 10

    Write-Verbose $JSON

    if ($PSCmdlet.ShouldProcess($Name)) {
        Invoke-HuduRequest -Method post -Resource '/api/v1/asset_layouts' -Body $JSON
    }
}
#EndRegion './Public/New-HuduAssetLayout.ps1' 156
#Region './Public/New-HuduBaseURL.ps1' -1

function New-HuduBaseURL {
    <#
    .SYNOPSIS
    Set Hudu Base URL

    .DESCRIPTION
    In order to access the Hudu API the Base URL must be set

    .PARAMETER BaseURL
    Url with no trailing slash e.g. https://demo.huducloud.com

    .EXAMPLE
    New-HuduBaseURL -BaseURL https://demo.huducloud.com

    .NOTES
    General notes
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Scope = 'Function')]
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $false,
            ValueFromPipeline = $true)]
        [String]
        $BaseURL
    )
    process {
        if (!$BaseURL) {
            $BaseURL = Read-Host -Prompt 'Please enter your Hudu Base URL with no trailing /, for example https://demo.huducloud.com :'
        }
            
        $Protocol = $BaseURL[0..7] -join ''
            if ($Protocol -ne 'https://') {
                if ($Protocol -like 'http://*') {
                    Write-Warning "Non HTTPS Base URL was set, rewriting URL to be secure transport only. If connection fails please make sure hostname is correct and HTTPS is enabld."
                    $BaseURL = $BaseURL.Replace('http://','https://')
                }
                else {
                    Write-Warning "No protocol was specified, adding https:// to the beginning of the specified hostname"
                    $BaseURL = "https://$BaseURL"
                }
            }
        
        Set-Variable -Name 'Int_HuduBaseURL' -Value $BaseURL -Visibility Private -Scope script -Force

        if ($script:Int_HuduAPIKey) {
            [version]$Version = (Get-HuduAppInfo).version
            if ($Version -lt $script:HuduRequiredVersion) {
                Write-Warning "A connection error occured or Hudu version is below $script:HuduRequiredVersion"
            }
        }
    }
}
#EndRegion './Public/New-HuduBaseURL.ps1' 53
#Region './Public/New-HuduCompany.ps1' -1

function New-HuduCompany {
    <#
    .SYNOPSIS
    Create a company

    .DESCRIPTION
    Uses Hudu API to create a new company

    .PARAMETER Name
    Company name

    .PARAMETER Nickname
    Company nickname

    .PARAMETER CompanyType
    Company type

    .PARAMETER AddressLine1
    Address line 1

    .PARAMETER AddressLine2
    Address line 2

    .PARAMETER City
    City

    .PARAMETER State
    State

    .PARAMETER Zip
    Zip

    .PARAMETER CountryName
    Country

    .PARAMETER PhoneNumber
    Phone number

    .PARAMETER FaxNumber
    Fax number

    .PARAMETER Website
    Website

    .PARAMETER IdNumber
    Company id number

    .PARAMETER ParentCompanyId
    Parent company id number

    .PARAMETER Notes
    Parameter description

    .PARAMETER Slug
    Url identifier

    .EXAMPLE
    New-HuduCompany -Name 'Company name'

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [String]$Name,

        [String]$Nickname = '',

        [Alias('company_type')]
        [String]$CompanyType = '',

        [Alias('address_line_1')]
        [String]$AddressLine1 = '',

        [Alias('address_line_2')]
        [String]$AddressLine2 = '',

        [String]$City = '',

        [String]$State = '',

        [Alias('PostalCode', 'PostCode')]
        [String]$Zip = '',

        [Alias('country_name')]
        [String]$CountryName = '',

        [Alias('phone_number')]
        [String]$PhoneNumber = '',

        [Alias('fax_number')]
        [String]$FaxNumber = '',

        [String]$Website = '',

        [Alias('id_number')]
        [String]$IdNumber = '',

        [Alias('parent_company_id')]
        [int]$ParentCompanyId,

        [String]$Notes = '',

        [string]$Slug
    )


    $Company = [ordered]@{company = [ordered]@{} }

    $Company.company.add('name', $Name)
    if (-not ([string]::IsNullOrEmpty($Nickname))) { $Company.company.add('nickname', $Nickname) }
    if (-not ([string]::IsNullOrEmpty($Nickname))) { $Company.company.add('company_type', $CompanyType) }
    if (-not ([string]::IsNullOrEmpty($AddressLine1))) { $Company.company.add('address_line_1', $AddressLine1) }
    if (-not ([string]::IsNullOrEmpty($AddressLine2))) { $Company.company.add('address_line_2', $AddressLine2) }
    if (-not ([string]::IsNullOrEmpty($City))) { $Company.company.add('city', $City) }
    if (-not ([string]::IsNullOrEmpty($State))) { $Company.company.add('state', $State) }
    if (-not ([string]::IsNullOrEmpty($Zip))) { $Company.company.add('zip', $Zip) }
    if (-not ([string]::IsNullOrEmpty($CountryName))) { $Company.company.add('country_name', $CountryName) }
    if (-not ([string]::IsNullOrEmpty($PhoneNumber))) { $Company.company.add('phone_number', $PhoneNumber) }
    if (-not ([string]::IsNullOrEmpty($FaxNumber))) { $Company.company.add('fax_number', $FaxNumber) }
    if (-not ([string]::IsNullOrEmpty($Website))) { $Company.company.add('website', $Website) }
    if (-not ([string]::IsNullOrEmpty($IdNumber))) { $Company.company.add('id_number', $IdNumber) }
    if (-not ([string]::IsNullOrEmpty($ParentCompanyId))) { $Company.company.add('parent_company_id', $ParentCompanyId) }
    if (-not ([string]::IsNullOrEmpty($Notes))) { $Company.company.add('notes', $Notes) }
    if (-not ([string]::IsNullOrEmpty($Slug))) { $Company.company.add('slug', $Slug) }

    $JSON = $Company | ConvertTo-Json -Depth 10
    Write-Verbose $JSON

    if ($PSCmdlet.ShouldProcess($Name)) {
        Invoke-HuduRequest -Method post -Resource '/api/v1/companies' -Body $JSON
    }
}
#EndRegion './Public/New-HuduCompany.ps1' 133
#Region './Public/New-HuduCustomHeaders.ps1' -1

function New-HuduCustomHeaders {
    <#
    .SYNOPSIS
    Set Hudu custom headers to be injected into each request

    .DESCRIPTION
    There may be times when one might need to use custom headers e.g. Service Tokens for Cloudflare Zero Trust

    .PARAMETER Headers
    Hashtable with the Custom Headers that need to be injected into each request

    .EXAMPLE
    New-HuduCustomHeaders -Headers @{"CF-Access-Client-Id" = "x"; "CF-Access-Client-Secret" = "y"}

    .NOTES
    General notes
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Scope = 'Function')]
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true,
            ValueFromPipeline = $true)]
        [hashtable]
        $Headers
    )
    process {
        if ($Headers.Count -eq 0) {
            Write-Host "Empty Custom Header hashtable was provided, no Custom Headers will be set"
            return 0
        }
        
        Set-Variable -Name 'Int_HuduCustomHeaders' -Value $Headers -Visibility Private -Scope script -Force
    }
}
#EndRegion './Public/New-HuduCustomHeaders.ps1' 35
#Region './Public/New-HuduFolder.ps1' -1

function New-HuduFolder {
    <#
    .SYNOPSIS
    Create a Folder

    .DESCRIPTION
    Uses Hudu API to create a new folder

    .PARAMETER Name
    Name of the folder

    .PARAMETER Icon
    Folder Icon

    .PARAMETER Description
    Folder description

    .PARAMETER ParentFolderId
    Parent folder ID

    .PARAMETER CompanyId
    Company id

    .EXAMPLE
    New-HuduFolder -Name 'Test folder' -CompanyId 1

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [String]$Name,
        [String]$Icon = '',
        [String]$Description = '',
        [Alias('parent_folder_id')]
        [Int]$ParentFolderId = '',
        [Alias('company_id')]
        [Int]$CompanyId = ''
    )

    $Folder = [ordered]@{folder = [ordered]@{} }

    $Folder.folder.add('name', $Name)

    if ($Icon) {
        $Folder.folder.add('icon', $Icon)
    }

    if ($Description) {
        $Folder.folder.add('description', $Description)
    }

    if ($ParentFolderId) {
        $Folder.folder.add('parent_folder_id', $ParentFolderId)
    }

    if ($CompanyId) {
        $Folder.folder.add('company_id', $CompanyId)
    }

    $JSON = $Folder | ConvertTo-Json

    if ($PSCmdlet.ShouldProcess($Name)) {
        Invoke-HuduRequest -Method post -Resource '/api/v1/folders' -Body $JSON
    }
}
#EndRegion './Public/New-HuduFolder.ps1' 66
#Region './Public/New-HuduPassword.ps1' -1

function New-HuduPassword {
    <#
    .SYNOPSIS
    Create a Password

    .DESCRIPTION
    Uses Hudu API to create a new password

    .PARAMETER Name
    Name of the password

    .PARAMETER CompanyId
    Company id

    .PARAMETER PasswordableType
    Asset type for the password

    .PARAMETER PasswordableId
    Asset id for the password

    .PARAMETER InPortal
    Boolean for in portal

    .PARAMETER Password
    Password

    .PARAMETER OTPSecret
    OTP secret

    .PARAMETER URL
    Password URL

    .PARAMETER Username
    Username

    .PARAMETER Description
    Password description

    .PARAMETER PasswordType
    Password type

    .PARAMETER PasswordFolderId
    Password folder id

    .PARAMETER Slug
    Url identifier

    .EXAMPLE
    New-HuduPassword -Name 'Some website password' -Username 'user@domain.com' -Password '12345'

    #>
    [CmdletBinding(SupportsShouldProcess)]
    # This will silence the warning for variables with Password in their name.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingUsernameAndPasswordParams', '')]
    Param (
        [Parameter(Mandatory = $true)]
        [String]$Name,

        [Alias('company_id')]
        [Parameter(Mandatory = $true)]
        [Int]$CompanyId,

        [Alias('passwordable_type')]
        [String]$PasswordableType = '',

        [Alias('passwordable_id')]
        [int]$PasswordableId = '',

        [Alias('in_portal')]
        [Bool]$InPortal = $false,

        [Parameter(Mandatory = $true)]
        [String]$Password = '',

        [Alias('otp_secret')]
        [string]$OTPSecret = '',

        [String]$URL = '',

        [String]$Username = '',

        [String]$Description = '',

        [Alias('password_type')]
        [String]$PasswordType = '',

        [Alias('password_folder_id')]
        [int]$PasswordFolderId,

        [string]$Slug
    )

    $AssetPassword = [ordered]@{asset_password = [ordered]@{} }

    $AssetPassword.asset_password.add('name', $Name)
    $AssetPassword.asset_password.add('company_id', $CompanyId)
    $AssetPassword.asset_password.add('password', $Password)
    $AssetPassword.asset_password.add('in_portal', $InPortal)

    if ($PasswordableType) {
        $AssetPassword.asset_password.add('passwordable_type', $PasswordableType)
    }
    if ($PasswordableId) {
        $AssetPassword.asset_password.add('passwordable_id', $PasswordableId)
    }

    if ($OTPSecret) {
        $AssetPassword.asset_password.add('otp_secret', $OTPSecret)
    }

    if ($URL) {
        $AssetPassword.asset_password.add('url', $URL)
    }

    if ($Username) {
        $AssetPassword.asset_password.add('username', $Username)
    }

    if ($Description) {
        $AssetPassword.asset_password.add('description', $Description)
    }

    if ($PasswordType) {
        $AssetPassword.asset_password.add('password_type', $PasswordType)
    }

    if ($PasswordFolderId) {
        $AssetPassword.asset_password.add('password_folder_id', $PasswordFolderId)
    }

    if ($Slug) {
        $AssetPassword.asset_password.add('slug', $Slug)
    }

    $JSON = $AssetPassword | ConvertTo-Json -Depth 10

    if ($PSCmdlet.ShouldProcess($Name)) {
        Invoke-HuduRequest -Method post -Resource '/api/v1/asset_passwords' -Body $JSON
    }
}
#EndRegion './Public/New-HuduPassword.ps1' 142
#Region './Public/New-HuduPublicPhoto.ps1' -1

function New-HuduPublicPhoto {
    <#
    .SYNOPSIS
    Create a Public Photo

    .DESCRIPTION
    Uses Hudu API to upload an image for use in an asset or article

    .PARAMETER FilePath
    Path to the image

    .PARAMETER RecordId
    Record id to associate with the photo

    .PARAMETER RecordType
    Record type to associate with the photo

    .EXAMPLE
    New-HuduPublicPhoto -FilePath 'c:\path\to\image.png' -RecordId 1 -RecordType 'asset'

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Alias('record_id')]
        [int]$RecordId,

        [Alias('record_type')]
        [string]$RecordType
    )

    $File = Get-Item $FilePath
    $form = @{
        photo = $File
    }

    if ($RecordId) { $form['record_id'] = $RecordId }
    if ($RecordType) { $form['record_type'] = $RecordType }

    if ($PSCmdlet.ShouldProcess($File.FullName)) {
        Invoke-HuduRequest -Method POST -Resource '/api/v1/public_photos' -Form $form
    }
}
#EndRegion './Public/New-HuduPublicPhoto.ps1' 46
#Region './Public/New-HuduRelation.ps1' -1

function New-HuduRelation {
    <#
    .SYNOPSIS
    Create a Relation

    .DESCRIPTION
    Uses Hudu API to create relationships between objects

    .PARAMETER Description
    Give a description to the relation so you know why two things are related

    .PARAMETER FromableType
    The type of the FROM relation (Asset, Website, Procedure, AssetPassword, Company, Article)

    .PARAMETER FromableID
    The ID of the FROM relation

    .PARAMETER ToableType
    The type of the TO relation (Asset, Website, Procedure, AssetPassword, Company, Article)

    .PARAMETER ToableID
    The ID of the TO relation

    .PARAMETER IsInverse
    When a relation is created, it will also create another relation that is the inverse. When this is true, this relation is the inverse.

    .EXAMPLE
    An example

    .NOTES
    General notes
    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [String]$Description,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Asset', 'Website', 'Procedure', 'AssetPassword', 'Company', 'Article')]
        [Alias('fromable_type')]
        [String]$FromableType,

        [Alias('fromable_id')]
        [int]$FromableID,

        [Alias('toable_type')]
        [String]$ToableType,

        [Alias('toable_id')]
        [int]$ToableID,

        [Alias('is_inverse')]
        [string]$IsInverse
    )

    $Relation = [ordered]@{relation = [ordered]@{} }

    $Relation.relation.add('fromable_type', $FromableType)
    $Relation.relation.add('fromable_id', $FromableID)
    $Relation.relation.add('toable_type', $ToableType)
    $Relation.relation.add('toable_id', $ToableID)

    if ($Description) {
        $Relation.relation.add('description', $Description)
    }

    if ($ISInverse) {
        $Relation.relation.add('is_inverse', $ISInverse)
    }

    $JSON = $Relation | ConvertTo-Json -Depth 100

    if ($PSCmdlet.ShouldProcess($FromableType)) {
        Invoke-HuduRequest -Method post -Resource '/api/v1/relations' -Body $JSON
    }
}
#EndRegion './Public/New-HuduRelation.ps1' 76
#Region './Public/New-HuduUpload.ps1' -1

function New-HuduUpload {
    <#
    .SYNOPSIS
    Create a Upload

    .DESCRIPTION
    Uses Hudu API to upload a file for use in an asset. RecordType can be of 'asset','website','procedure','assetpassword','comapny','article'.

    .PARAMETER FilePath
    Path to the file

    .PARAMETER RecordId
    Record id to associate with the Upload

    .PARAMETER RecordType
    Record type to associate with the Upload

    .EXAMPLE
    New-HuduUpload -FilePath 'c:\path\to\file.png' -RecordId 1 -RecordType 'asset'

    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [Alias('record_id','recordid')]
        [int]$uploadable_id,

        [Parameter(Mandatory)]
        [Alias('record_type','recordtype')]
        [ValidateSet('Asset', 'Website', 'Procedure', 'AssetPassword', 'Company', 'Article')]
        [string]$uploadable_type
    )

    $File = Get-Item $FilePath
    
    $form = @{
        file = $File
        "upload[uploadable_id]" = $uploadable_id
        "upload[uploadable_type]" = $uploadable_type
    }

    if ($PSCmdlet.ShouldProcess($File.FullName)) {
        Invoke-HuduRequest -Method POST -Resource '/api/v1/uploads' -Form $form
    }
}
#EndRegion './Public/New-HuduUpload.ps1' 49
#Region './Public/New-HuduWebsite.ps1' -1

function New-HuduWebsite {
    <#
    .SYNOPSIS
    Create a Website

    .DESCRIPTION
    Uses Hudu API to create a website

    .PARAMETER Name
    Website name (e.g. https://domain.com)

    .PARAMETER Notes
    Used to add additional notes to a website

    .PARAMETER Paused
    When true, website monitoring is paused

    .PARAMETER CompanyId
    Used to associate website with company

    .PARAMETER DisableDNS
    When true, dns monitoring is paused.

    .PARAMETER DisableSSL
    When true, ssl cert monitoring is paused.

    .PARAMETER DisableWhois
    When true, whois monitoring is paused.

    .PARAMETER Slug
    Url identifier

    .EXAMPLE
    New-HuduWebsite -CompanyId 1 -Name https://domain.com

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [String]$Name,

        [String]$Notes = '',

        [String]$Paused = '',

        [Alias('company_id')]
        [Parameter(Mandatory = $true)]
        [Int]$CompanyId,

        [Alias('disable_dns')]
        [String]$DisableDNS = '',

        [Alias('disable_ssl')]
        [String]$DisableSSL = '',

        [Alias('disable_whois')]
        [String]$DisableWhois = '',

        [string]$Slug
    )

    $Website = [ordered]@{website = [ordered]@{} }

    $Website.website.add('name', $Name)

    if ($Notes) {
        $Website.website.add('notes', $Notes)
    }

    if ($Paused) {
        $Website.website.add('paused', $Paused)
    }

    $Website.website.add('company_id', $CompanyId)

    if ($DisableDNS) {
        $Website.website.add('disable_dns', $DisableDNS)
    }

    if ($DisableSSL) {
        $Website.website.add('disable_ssl', $DisableSSL)
    }

    if ($DisableWhois) {
        $Website.website.add('disable_whois', $DisableWhois)
    }

    if ($Slug) {
        $Website.website.add('slug', $Slug)
    }

    $JSON = $Website | ConvertTo-Json

    if ($PSCmdlet.ShouldProcess($Name)) {
        Invoke-HuduRequest -Method post -Resource '/api/v1/websites' -Body $JSON
    }
}
#EndRegion './Public/New-HuduWebsite.ps1' 98
#Region './Public/Remove-HuduAPIKey.ps1' -1

function Remove-HuduAPIKey {
    <#
    .SYNOPSIS
    Remove API key

    .DESCRIPTION
    Unsets the variable for the Hudu API Key

    .EXAMPLE
    Remove-HuduAPIKey

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param()

    if ($PSCmdlet.ShouldProcess('API Key')) {
        Remove-Variable -Name 'Int_HuduAPIKey' -Scope script -Force
    }
}
#EndRegion './Public/Remove-HuduAPIKey.ps1' 20
#Region './Public/Remove-HuduArticle.ps1' -1

function Remove-HuduArticle {
    <#
    .SYNOPSIS
    Delete a Knowledge Base Article

    .DESCRIPTION
    Uses Hudu API to remove a KB article

    .PARAMETER Id
    Id of the requested article

    .EXAMPLE
    Remove-HuduArticle -Id 1

    .NOTES
    General notes
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    Param (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [Int]$Id
    )
    process {
        if ($PSCmdlet.ShouldProcess($Id)) {
            Invoke-HuduRequest -Method delete -Resource "/api/v1/articles/$Id"
        }
    }
}
#EndRegion './Public/Remove-HuduArticle.ps1' 29
#Region './Public/Remove-HuduAsset.ps1' -1

function Remove-HuduAsset {
    <#
    .SYNOPSIS
    Delete an Asset

    .DESCRIPTION
    Uses Hudu API to remove an Asset from a company

    .PARAMETER Id
    Id of the requested Asset

    .PARAMETER CompanyId
    Id of the requested parent Company

    .EXAMPLE
    Remove-HuduAsset -CompanyId 1 -Id 1

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    Param (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [Int]$Id,
        [Alias('company_id')]
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [Int]$CompanyId
    )

    process {
        if ($PSCmdlet.ShouldProcess($Id)) {
            Invoke-HuduRequest -Method delete -Resource "/api/v1/companies/$CompanyId/assets/$Id"
        }
    }
}
#EndRegion './Public/Remove-HuduAsset.ps1' 34
#Region './Public/Remove-HuduBaseURL.ps1' -1

function Remove-HuduBaseURL {
    <#
    .SYNOPSIS
    Remove base URL

    .DESCRIPTION
    Unsets the Hudu Base URL variable

    .EXAMPLE
    Remove-HuduBaseURL

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param()
    if ($PSCmdlet.ShouldProcess('Base URL')) {
        Remove-Variable -Name 'Int_HuduBaseURL' -Scope script -Force
    }
}
#EndRegion './Public/Remove-HuduBaseURL.ps1' 19
#Region './Public/Remove-HuduCompany.ps1' -1

function Remove-HuduCompany {
    <#
    .SYNOPSIS
    Delete a Website

    .DESCRIPTION
    Uses Hudu API to delete a company

    .PARAMETER Id
    Id of the Company to delete

    .EXAMPLE
    Remove-HuduCompany -Id 1

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    Param (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [Int]$Id
    )

    process {
        if ($PSCmdlet.ShouldProcess($Id)) {
            Invoke-HuduRequest -Method delete -Resource "/api/v1/companies/$Id"
        }
    }
}
#EndRegion './Public/Remove-HuduCompany.ps1' 28
#Region './Public/Remove-HuduCustomHeaders.ps1' -1

function Remove-HuduCustomHeaders {
    <#
    .SYNOPSIS
    Remove Custom Headers that are injected into each request

    .DESCRIPTION
    Unsets the Hudu Custom Header variable

    .EXAMPLE
    Remove-HuduCustomHeaders

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param()
    if ($PSCmdlet.ShouldProcess('Custom Headers')) {
        Remove-Variable -Name 'Int_HuduCustomHeaders' -Scope script -Force
    }
}
#EndRegion './Public/Remove-HuduCustomHeaders.ps1' 19
#Region './Public/Remove-HuduMagicDash.ps1' -1

function Remove-HuduMagicDash {
    <#
    .SYNOPSIS
    Delete a Magic Dash Item

    .DESCRIPTION
    Uses Hudu API to remove Magic Dash by Id or Title and Company Name

    .PARAMETER Title
    Title of the Magic Dash

    .PARAMETER CompanyName
    Company Name

    .PARAMETER Id
    Id of the Magic Dash

    .EXAMPLE
    Remove-HuduMagicDash -Id 1

    .EXAMPLE
    Remove-HuduMagicDash -Title 'Microsoft 365' -CompanyName 'AcmeCorp'

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Id')]
    Param (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true, ParameterSetName = 'TitleCompany')]
        [String]$Title,

        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true, ParameterSetName = 'TitleCompany')]
        [Alias('company_name')]
        [String]$CompanyName,

        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true, ParameterSetName = 'Id')]
        [int]$Id
    )

    process {
        if ($id) {
            if ($PSCmdlet.ShouldProcess($Id)) {
                $null = Invoke-HuduRequest -Method delete -Resource "/api/v1/magic_dash/$Id"
            }
        } else {
            $MagicDash = @{}

            $MagicDash.add('title', $Title)
            $MagicDash.add('company_name', $CompanyName)

            $JSON = $MagicDash | ConvertTo-Json

            if ($PSCmdlet.ShouldProcess("$Company - $Title")) {
                $null = Invoke-HuduRequest -Method delete -Resource '/api/v1/magic_dash' -Body $JSON
            }
        }
    }
}
#EndRegion './Public/Remove-HuduMagicDash.ps1' 57
#Region './Public/Remove-HuduPassword.ps1' -1

function Remove-HuduPassword {
    <#
    .SYNOPSIS
    Delete a Password

    .DESCRIPTION
    Uses Hudu API to remove asset password

    .PARAMETER Id
    Id of the password

    .EXAMPLE
    Remove-HuduPassword -Id 1

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    Param (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [Int]$Id
    )
    process {
        if ($PSCmdlet.ShouldProcess($Id)) {
            Invoke-HuduRequest -Method delete -Resource "/api/v1/asset_passwords/$Id"
        }
    }
}
#EndRegion './Public/Remove-HuduPassword.ps1' 27
#Region './Public/Remove-HuduRelation.ps1' -1

function Remove-HuduRelation {
    <#
    .SYNOPSIS
    Delete a Relation

    .DESCRIPTION
    Uses Hudu API to delete object relationships

    .PARAMETER Id
    Id of the requested Relation

    .EXAMPLE
    Remove-HuduRelation -Id 1

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    Param (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [Int]$Id
    )

    process {
        if ($PSCmdlet.ShouldProcess($Id)) {
            Invoke-HuduRequest -Method delete -Resource "/api/v1/relations/$Id"
        }
    }
}
#EndRegion './Public/Remove-HuduRelation.ps1' 28
#Region './Public/Remove-HuduUpload.ps1' -1

function Remove-HuduUpload {
    <#
    .SYNOPSIS
    Delete an Upload by ID

    .DESCRIPTION
    Calls Hudu API to delete uploads by specifying the ID value

    .EXAMPLE
    Remove-HuduUpload

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    Param(
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [Int]$Id
    )

    process {
        if ($PSCmdlet.ShouldProcess($Id)) {
            Invoke-HuduRequest -Method delete -Resource "/api/v1/uploads/$Id"
        }
    }
    
}
#EndRegion './Public/Remove-HuduUpload.ps1' 26
#Region './Public/Remove-HuduWebsite.ps1' -1

function Remove-HuduWebsite {
    <#
    .SYNOPSIS
    Delete a Website

    .DESCRIPTION
    Uses Hudu API to delete a website

    .PARAMETER Id
    Id of the requested Website

    .EXAMPLE
    Remove-HuduWebsite -Id 1

    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    Param (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [Int]$Id
    )

    process {
        if ($PSCmdlet.ShouldProcess($Id)) {
            Invoke-HuduRequest -Method delete -Resource "/api/v1/websites/$Id"
        }
    }
}
#EndRegion './Public/Remove-HuduWebsite.ps1' 28
#Region './Public/Set-HuduArticle.ps1' -1

function Set-HuduArticle {
    <#
    .SYNOPSIS
    Update a Knowledge Base Article

    .DESCRIPTION
    Uses Hudu API to update KB Article

    .PARAMETER Name
    Name of the Article

    .PARAMETER Content
    Article Content

    .PARAMETER EnableSharing
    Set article to public and generate a URL

    .PARAMETER FolderId
    Used to associate article with folder

    .PARAMETER CompanyId
    Used to associate article with company

    .PARAMETER ArticleId
    Id of the requested article

    .PARAMETER Slug
    Url identifier

    .EXAMPLE
    Set-HuduArticle -ArticleId 1 -Name 'Article Name' -Content '<h1>New article contents</h1>'

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [String]$Name,

        [String]$Content,
        [switch]$EnableSharing,

        [Alias('folder_id')]
        [Int]$FolderId = '',

        [Alias('company_id')]
        [Int]$CompanyId = '',

        [Alias('article_id', 'id')]
        [Parameter(Mandatory = $true)]
        [Int]$ArticleId,

        [string]$Slug
    )
    
    $Object = Get-HuduArticles -Id $ArticleId
    $Article = [ordered]@{article = $Object.article }

    if ($Name) {
        $Article.article.name = $Name
    }
    
    if ($Content) {
        $Article.article.content = $Content
    }
    
    if ($FolderId) {
        $Article.article.folder_id = $FolderId
    }

    if ($CompanyId) {
        $Article.article.company_id = $CompanyId
    }

    if ($EnableSharing.IsPresent) {
        $Article.article.enable_sharing = $true
    }

    if ($Slug) {
        $Article.article.slug = $Slug
    }

    $JSON = $Article | ConvertTo-Json -Depth 10

    if ($PSCmdlet.ShouldProcess($Name)) {
        Invoke-HuduRequest -Method put -Resource "/api/v1/articles/$ArticleId" -Body $JSON
    }
}
#EndRegion './Public/Set-HuduArticle.ps1' 87
#Region './Public/Set-HuduArticleArchive.ps1' -1

function Set-HuduArticleArchive {
    <#
    .SYNOPSIS
    Archive/Unarchive a Knowledge Base Article

    .DESCRIPTION
    Uses Hudu API to archive or unarchive an article

    .PARAMETER Id
    Id of the requested article

    .PARAMETER Archive
    Boolean for archive status

    .EXAMPLE
    Set-HuduArticleArchive -Id 1 -Archive $true

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [Int]$Id,
        [Parameter(Mandatory = $true)]
        [Bool]$Archive
    )

    if ($Archive) {
        $Action = 'archive'
    } else {
        $Action = 'unarchive'
    }

    if ($PSCmdlet.ShouldProcess($Id)) {
        Invoke-HuduRequest -Method put -Resource "/api/v1/articles/$Id/$Action"
    }
}
#EndRegion './Public/Set-HuduArticleArchive.ps1' 37
#Region './Public/Set-HuduAsset.ps1' -1

function Set-HuduAsset {
    <#
    .SYNOPSIS
    Update an Asset

    .DESCRIPTION
    Uses Hudu API to update an Asset

    .PARAMETER Name
    Name of the Asset

    .PARAMETER CompanyId
    Company id of the Asset

    .PARAMETER AssetLayoutId
    Asset layout id

    .PARAMETER Fields
    List of fields

    .PARAMETER AssetId
    Id of the requested Asset

    .PARAMETER PrimarySerial
    Primary serial number

    .PARAMETER PrimaryMail
    Primary mail

    .PARAMETER PrimaryModel
    Primary model

    .PARAMETER PrimaryManufacturer
    Primary manufacturer

    .PARAMETER Slug
    Url identifier

    .EXAMPLE
    Set-HuduAsset -AssetId 1 -CompanyId 1 -Fields @(@{'field_name'='Field Value'})

    .NOTES
    General notes
    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [String]$Name,

        [Alias('company_id')]
        [Int]$CompanyId,

        [Alias('asset_layout_id')]
        [Int]$AssetLayoutId,

        [Array]$Fields,

        [Alias('asset_id','assetid')]
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, [int]::MaxValue)]
        [Int]$Id,
        
        [Alias('primary_serial')]
        [string]$PrimarySerial,

        [Alias('primary_mail')]
        [string]$PrimaryMail,

        [Alias('primary_model')]
        [string]$PrimaryModel,

        [Alias('primary_manufacturer')]
        [string]$PrimaryManufacturer,

        [string]$Slug
    )
    
    $Object = Get-HuduAssets -id $Id | Select-Object name,asset_layout_id,company_id,slug,primary_serial,primary_model,primary_mail,id,primary_manufacturer,@{n='custom_fields';e={$_.fields | ForEach-Object {[pscustomobject]@{$_.label.replace(' ','_').tolower()= $_.value}}}}
    if ($Object) {
        $Asset = [ordered]@{asset = $Object }
        $CompanyId = $Object.company_id
    
        if ($Name) {
            $Asset.asset.name = $Name
        }
    
        if ($AssetLayoutId) {
            $Asset.asset.asset_layout_id = $AssetLayoutId
        }
        
        if ($PrimarySerial) {
            $Asset.asset.primary_serial = $PrimarySerial
        }
    
        if ($PrimaryMail) {
            $Asset.asset.primary_mail = $PrimaryMail
        }
    
        if ($PrimaryModel) {
            $Asset.asset.primary_model = $PrimaryModel
        }
    
        if ($PrimaryManufacturer) {
            $Asset.asset.primary_manufacturer = $PrimaryManufacturer
        }
    
        if ($Fields) {
            $Asset.asset.custom_fields = $Fields
        }
    
        if ($Slug) {
            $Asset.asset.slug = $Slug
        }
    
        $JSON = $Asset | ConvertTo-Json -Depth 10
    
        if ($PSCmdlet.ShouldProcess("ID: $($Asset.id) Name: $($Asset.Name)", "Set Hudu Asset")) {
            Invoke-HuduRequest -Method put -Resource "/api/v1/companies/$CompanyId/assets/$Id" -Body $JSON
        }
    } else {
    throw "A valid asset could not be found to update, please double check the ID and try again"
    }
}
#EndRegion './Public/Set-HuduAsset.ps1' 123
#Region './Public/Set-HuduAssetArchive.ps1' -1

function Set-HuduAssetArchive {
    <#
    .SYNOPSIS
    Archive/Unarchive an Asset

    .DESCRIPTION
    Uses Hudu API to archive or unarchive an asset

    .PARAMETER Id
    Id of the requested Asset

    .PARAMETER CompanyId
    Id of the requested parent company

    .PARAMETER Archive
    Boolean for archive status

    .EXAMPLE
    Set-HuduAssetArchive -Id 1 -CompanyId 1 -Archive $true

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [Int]$Id,
        [Alias('company_id')]
        [Parameter(Mandatory = $true)]
        [Int]$CompanyId,
        [Parameter(Mandatory = $true)]
        [Bool]$Archive
    )

    if ($Archive) {
        $Action = 'archive'
    } else {
        $Action = 'unarchive'
    }

    if ($PSCmdlet.ShouldProcess($Id)) {
        Invoke-HuduRequest -Method put -Resource "/api/v1/companies/$CompanyId/assets/$Id/$Action"
    }
}
#EndRegion './Public/Set-HuduAssetArchive.ps1' 43
#Region './Public/Set-HuduAssetLayout.ps1' -1

function Set-HuduAssetLayout {
    <#
    .SYNOPSIS
    Update an Asset Layout

    .DESCRIPTION
    Uses Hudu API to update an Asset Layout

    .PARAMETER Id
    Id of the requested Asset Layout

    .PARAMETER Name
    Name of the Asset Layout

    .PARAMETER Icon
    Icon class name, example: "fas fa-home"

    .PARAMETER Color
    Hex code for background color, example: #000000

    .PARAMETER IconColor
    Hex code for background color, example: #000000

    .PARAMETER IncludePasswords
    Boolean to include passwords

    .PARAMETER IncludePhotos
    Boolean to include photos

    .PARAMETER IncludeComments
    Boolean to include comments

    .PARAMETER IncludeFiles
    Boolean to include files

    .PARAMETER PasswordTypes
    List of password types, separated with new line characters

    .PARAMETER Slug
    Url identifier

    .PARAMETER Fields
    Array of hashtable or custom objects representing layout fields. Most field types only require a label and type.
    Valid field types are: Text, RichText, Heading, CheckBox, Website (aka Link), Password (aka ConfidentialText), Number, Date, DropDown, Embed, Email (aka CopyableText), Phone, AssetLink
    Field types are Case Sensitive as of Hudu V2.27 due to a known issue with asset type validation.

    .EXAMPLE
    Set-HuduAssetLayout -Id 12 -Name 'Test asset layout' -Icon 'fas fa-home' -IncludePassword $true

    .EXAMPLE
    Set-HuduAssetLayout -Id 12 -Fields @(
        @{label = 'Test field'; 'field_type' = 'Text'}
    )
    #>
    [CmdletBinding(SupportsShouldProcess)]
    # This will silence the warning for variables with Password in their name.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '')]
    Param (
        [Parameter(Mandatory = $true)]
        [Int]$Id,

        [String]$Name,

        [String]$Icon,

        [String]$Color,

        [Alias('icon_color')]
        [String]$IconColor,

        [Alias('include_passwords')]
        [bool]$IncludePasswords,

        [Alias('include_photos')]
        [bool]$IncludePhotos,

        [Alias('include_comments')]
        [bool]$IncludeComments,

        [Alias('include_files')]
        [bool]$IncludeFiles,

        [Alias('password_types')]
        [String]$PasswordTypes = '',

        [bool]$Active,

        [string]$Slug,

        [array]$Fields
    )

    foreach ($Field in $Fields) {
        $Field.show_in_list = [System.Convert]::ToBoolean($Field.show_in_list)
        $Field.required = [System.Convert]::ToBoolean($Field.required)
        $Field.expiration = [System.Convert]::ToBoolean($Field.expiration)
        # A bug in versions of Hudu 2.27 and earlier can cause asset layouts to become corrupted if the field type value is not properly cased.
        switch ($field.'field_type') {
            'text'              { $field.'field_type' = 'Text' }
            'richtext'          { $field.'field_type' = 'RichText' }
            'heading'           { $field.'field_type' = 'Heading' }
            'checkbox'          { $field.'field_type' = 'CheckBox' }
            'number'            { $field.'field_type' = 'Number' }
            'date'              { $field.'field_type' = 'Date' }
            'dropdown'          { $field.'field_type' = 'Dropdown' }
            'embed'             { $field.'field_type' = 'Embed' }
            'phone'             { $field.'field_type' = 'Phone' }
            ('email'    -or 'copyabletext')     { $field.'field_type' = 'Email' }
            ('assettag' -or 'assetlink')        { $field.'field_type' = 'AssetTag' }
            ('website'  -or 'link')             { $field.'field_type' = 'Website' }
            ('password' -or 'confidentialtext') { $field.'field_type' = 'Password' }
            Default { Write-Error "Invalid field type: $($field.'field_type') found in field $($field.name)"; break }
        }
    }
    $Object = Get-HuduAssetLayouts -id $Id

    $AssetLayout = [ordered]@{asset_layout = $Object }
    #$AssetLayout.asset_layout = $Object

    if ($Name) {
        $AssetLayout.asset_layout.name = $Name
    }
    
    if ($Icon) {
        $AssetLayout.asset_layout.icon = $Icon
    }

    if ($Color) {
        $AssetLayout.asset_layout.color = $Color
    }

    if ($IconColor) {
        $AssetLayout.asset_layout.icon_color = $IconColor
    }

    if ($Fields) {
        $AssetLayout.asset_layout.fields = $Fields
    }

    if ($IncludePasswords) {
        $AssetLayout.asset_layout.include_passwords = [System.Convert]::ToBoolean($IncludePasswords)
    }

    if ($IncludePhotos) {
        $AssetLayout.asset_layout.include_photos = [System.Convert]::ToBoolean($IncludePhotos)
    }

    if ($IncludeComments) {
        $AssetLayout.asset_layout.include_comments = [System.Convert]::ToBoolean($IncludeComments)
    }

    if ($IncludeFiles) {
        $AssetLayout.asset_layout.include_files = [System.Convert]::ToBoolean($IncludeFiles)
    }

    if ($PasswordTypes) {
        $AssetLayout.asset_layout.password_types = $PasswordTypes
    }

    if ($SidebarFolderID) {
        $AssetLayout.asset_layout.sidebar_folder_id = $SidebarFolderID
    }

    if ($Slug) {
        $AssetLayout.asset_layout.slug = $Slug
    }

    if ($Active) {
        $AssetLayout.asset_layout.active = [System.Convert]::ToBoolean($Active)
    }

    $JSON = $AssetLayout | ConvertTo-Json -Depth 10

    if ($PSCmdlet.ShouldProcess($Id)) {
        Invoke-HuduRequest -Method put -Resource "/api/v1/asset_layouts/$Id" -Body $JSON
    }
}
#EndRegion './Public/Set-HuduAssetLayout.ps1' 178
#Region './Public/Set-HuduCompany.ps1' -1

function Set-HuduCompany {
    <#
    .SYNOPSIS
    Update a company

    .DESCRIPTION
    Uses Hudu API to update a Company

    .PARAMETER Id
    Id of the requested company

    .PARAMETER Name
    Name of the company

    .PARAMETER Nickname
    Nickname of the company

    .PARAMETER CompanyType
    Company type

    .PARAMETER AddressLine1
    Address line 1

    .PARAMETER AddressLine2
    Address line 2

    .PARAMETER City
    City

    .PARAMETER State
    State

    .PARAMETER Zip
    Zip

    .PARAMETER CountryName
    Country name

    .PARAMETER PhoneNumber
    Phone number

    .PARAMETER FaxNumber
    Fax number

    .PARAMETER Website
    Webste

    .PARAMETER IdNumber
    Id number

    .PARAMETER ParentCompanyId
    Parent company id

    .PARAMETER Notes
    Company notes

    .PARAMETER Slug
    Url identifier

    .EXAMPLE
    Set-HuduCompany -Id 1 -Name 'New company name'

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [Int]$Id,

        [String]$Name,

        [String]$Nickname = '',

        [Alias('company_type')]
        [String]$CompanyType = '',

        [Alias('address_line_1')]
        [String]$AddressLine1 = '',

        [Alias('address_line_2')]
        [String]$AddressLine2 = '',

        [String]$City = '',

        [String]$State = '',

        [Alias('PostalCode', 'PostCode')]
        [String]$Zip = '',

        [Alias('country_name')]
        [String]$CountryName = '',

        [Alias('phone_number')]
        [String]$PhoneNumber = '',

        [Alias('fax_number')]
        [String]$FaxNumber = '',

        [String]$Website = '',

        [Alias('id_number')]
        [String]$IdNumber = '',

        [Alias('parent_company_id')]
        [Int]$ParentCompanyId,

        [String]$Notes = '',

        [string]$Slug
    )

    $Object = Get-HuduCompanies -Id $Id

    $Company = [ordered]@{company = $Object }

    if ($Name) {
        $Company.company.name = $Name
    }

    if ($Nickname) {
        $Company.company.nickname = $Nickname
    }

    if ($CompanyType) {
        $Company.company.company_type = $CompanyType
    }

    if ($AddressLine1) {
        $Company.company.address_line_1 = $AddressLine1
    }

    if ($AddressLine2) {
        $Company.company.address_line_2 = $AddressLine2
    }

    if ($City) {
        $Company.company.city = $City
    }
    
    if ($State) {
        $Company.company.state = $State
    }

    if ($Zip) {
        $Company.company.zip = $Zip
    }

    if ($CountryName) {
        $Company.company.country_name = $CountryName
    }

    if ($PhoneNumber) {
        $Company.company.phone_number = $PhoneNumber
    }

    if ($FaxNumber) {
        $Company.company.fax_number = $FaxNumber
    }

    if ($Website) {
        $Company.company.website = $Website
    }

    if ($IdNumber) {
        $Company.company.id_number = $IdNumber
    }

    if ($ParentCompanyId) {
        $Company.company.parent_company_id = $ParentCompanyId
    }

    if ($Notes) {
        $Company.company.notes = $Notes
    }

    if ($Slug) {
        $Company.company.slug = $Slug
    }

    $JSON = $Company | ConvertTo-Json -Depth 10

    if ($PSCmdlet.ShouldProcess($Id)) {
        Invoke-HuduRequest -Method put -Resource "/api/v1/companies/$Id" -Body $JSON
    }
}
#EndRegion './Public/Set-HuduCompany.ps1' 185
#Region './Public/Set-HuduCompanyArchive.ps1' -1

function Set-HuduCompanyArchive {
    <#
    .SYNOPSIS
    Archive/Unarchive a company

    .DESCRIPTION
    Uses Hudu API to set archive status on a company

    .PARAMETER Id
    Id of the requested company

    .PARAMETER Archive
    Boolean for archive status

    .EXAMPLE
    Set-HuduCompanyArchive -Id 1 -Archive $true

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [Int]$Id,
        [Parameter(Mandatory = $true)]
        [Bool]$Archive
    )

    if ($Archive -eq $true) {
        $Action = 'archive'
    } else {
        $Action = 'unarchive'
    }
    if ($PSCmdlet.ShouldProcess($Id)) {
        Invoke-HuduRequest -Method put -Resource "/api/v1/companies/$Id/$Action"
    }
}
#EndRegion './Public/Set-HuduCompanyArchive.ps1' 36
#Region './Public/Set-HuduFolder.ps1' -1

function Set-HuduFolder {
    <#
    .SYNOPSIS
    Update a Folder

    .DESCRIPTION
    Uses Hudu API to update a folder

    .PARAMETER Id
    Id of the requested folder

    .PARAMETER Name
    Name of the folder

    .PARAMETER Icon
    Folder icon

    .PARAMETER Description
    Folder description

    .PARAMETER ParentFolderId
    Folder parent id

    .PARAMETER CompanyId
    Folder company id

    .EXAMPLE
    Set-HuduFolder -Id 1 -Name 'New folder name'

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [Int]$Id,

        [Parameter(Mandatory = $true)]
        [String]$Name,

        [String]$Icon = '',

        [String]$Description = '',

        [Alias('parent_folder_id')]
        [Int]$ParentFolderId = '',

        [Alias('company_id')]
        [Int]$CompanyId = ''
    )

    $Folder = [ordered]@{folder = [ordered]@{} }

    $Folder.folder.add('name', $Name)

    if ($icon) {
        $Folder.folder.add('icon', $Icon)
    }

    if ($Description) {
        $Folder.folder.add('description', $Description)
    }

    if ($ParentFolderId) {
        $Folder.folder.add('parent_folder_id', $ParentFolderId)
    }

    if ($CompanyId) {
        $Folder.folder.add('company_id', $CompanyId)
    }

    $JSON = $Folder | ConvertTo-Json

    if ($PSCmdlet.ShouldProcess($Id)) {
        Invoke-HuduRequest -Method put -Resource "/api/v1/folders/$Id" -Body $JSON
    }
}
#EndRegion './Public/Set-HuduFolder.ps1' 76
#Region './Public/Set-HuduIntegrationMatcher.ps1' -1

function Set-HuduIntegrationMatcher {
    <#
    .SYNOPSIS
    Update a Matcher

    .DESCRIPTION
    Uses Hudu API to set integration matchers

    .PARAMETER Id
    Id of the requested matcher

    .PARAMETER AcceptSuggestedMatch
    Set the Sync Id/Identifier to the suggested one

    .PARAMETER CompanyId
    Requested company id to match

    .PARAMETER PotentialCompanyId
    Potential company id to match

    .PARAMETER SyncId
    Sync id to match

    .PARAMETER Identifier
    Identifier to match

    .EXAMPLE
    Set-HuduIntegrationMatcher -Id 1 -AcceptSuggestedMatch

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [String]$Id,

        [Parameter(ParameterSetName = 'AcceptSuggestedMatch')]
        [switch]$AcceptSuggestedMatch,

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'SetCompanyId')]
        [Alias('company_id')]
        [String]$CompanyId,

        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [Alias('potential_company_id')]
        [String]$PotentialCompanyId,

        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [Alias('sync_id')]
        [String]$SyncId,

        [Parameter(ValueFromPipelineByPropertyName = $true)]
        [String]$Identifier
    )

    process {
        $Matcher = [ordered]@{matcher = [ordered]@{} }

        if ($AcceptSuggestedMatch) {
            $Matcher.matcher.add('company_id', $PotentialCompanyId) | Out-Null
        } else {
            $Matcher.matcher.add('company_id', $CompanyId) | Out-Null
        }

        if ($PotentialCompanyId) {
            $Matcher.matcher.add('potential_company_id', $PotentialCompanyId) | Out-Null
        }
        if ($SyncId) {
            $Matcher.matcher.add('sync_id', $SyncId) | Out-Null
        }
        if ($Identifier) {
            $Matcher.matcher.add('identifier', $identifier) | Out-Null
        }

        $JSON = $Matcher | ConvertTo-Json -Depth 10

        if ($PSCmdlet.ShouldProcess($Id)) {
            Invoke-HuduRequest -Method put -Resource "/api/v1/matchers/$Id" -Body $JSON
        }
    }
}
#EndRegion './Public/Set-HuduIntegrationMatcher.ps1' 81
#Region './Public/Set-HuduMagicDash.ps1' -1

function Set-HuduMagicDash {
    <#
    .SYNOPSIS
    Create or Update a Magic Dash Item

    .DESCRIPTION
    Magic Dash takes just simple key-pairs. Whether you want to add a new Magic Dash Item, or update one, you can use the same endpoint, so it is really easy! It uses the title, and company_name to match.

    .PARAMETER Title
    This is the title. If there is an existing Magic Dash Item with matching title and company_name, then it will match into that item.

    .PARAMETER CompanyName
    This is the attribute we use to match to an existing company. If there is an existing Magic Dash Item with matching title and company_name, then it will match into that item.

    .PARAMETER Message
    This will be the first content that will be displayed on the Magic Dash Item.

    .PARAMETER Icon
    Either fill this in, or image_url. Use a (FontAwesome icon for the header of a Magic Dash Item. Must be in the format of fas fa-circle

    .PARAMETER ImageURL
    Either fill this in, or icon. Used in the header of a Magic Dash Item.

    .PARAMETER ContentLink
    Either fill this in, or content, or leave both blank. Used to have a link to an external website.

    .PARAMETER Content
    Either fill this in, or content_link, or leave both blank. Fill in with HTML (tables, images, videos, etc.) to display more content in your Magic Dash Item.

    .PARAMETER Shade
    Use a different color for your Magic Dash Item for different contextual states. Options are to leave it blank, success, or danger

    .EXAMPLE
    Set-HuduMagicDash -Title 'Test Dash' -CompanyName 'Test Company' -Message 'This will be displayed first'

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [String]$Title,

        [Alias('company_name')]
        [Parameter(Mandatory = $true)]
        [String]$CompanyName,

        [Parameter(Mandatory = $true)]
        [String]$Message,

        [String]$Icon = '',

        [Alias('image_url')]
        [String]$ImageURL = '',

        [Alias('content_link')]
        [String]$ContentLink = '',

        [String]$Content = '',

        [String]$Shade = ''
    )

    if ($Icon -and $ImageURL) {
        Write-Error ('You can only use one of icon or image URL')
        exit 1
    }

    if ($content_link -and $content) {
        Write-Error ('You can only use one of content or content_link')
        exit 1
    }

    $MagicDash = [ordered]@{}

    if ($Title) {
        $MagicDash.add('title', $Title)
    }

    if ($CompanyName) {
        $MagicDash.add('company_name', $CompanyName)
    }

    if ($Message) {
        $MagicDash.add('message', $Message)
    }

    if ($Icon) {
        $MagicDash.add('icon', $Icon)
    }

    if ($ImageURL) {
        $MagicDash.add('image_url', $ImageURL)
    }

    if ($ContentLink) {
        $MagicDash.add('content_link', $ContentLink)
    }

    if ($Content) {
        $MagicDash.add('content', $Content)
    }

    if ($Shade) {
        $MagicDash.add('shade', $Shade)
    }

    $JSON = $MagicDash | ConvertTo-Json

    if ($PSCmdlet.ShouldProcess("$Companyname - $Title")) {
        Invoke-HuduRequest -Method post -Resource '/api/v1/magic_dash' -Body $JSON
    }
}
#EndRegion './Public/Set-HuduMagicDash.ps1' 112
#Region './Public/Set-HuduPassword.ps1' -1

function Set-HuduPassword {
    <#
    .SYNOPSIS
    Update a Password

    .DESCRIPTION
    Uses Hudu API to update a password

    .PARAMETER Id
    Id of the requested Password

    .PARAMETER Name
    Password name

    .PARAMETER CompanyId
    Id of requested company

    .PARAMETER PasswordableType
    Type of asset to associate with the password

    .PARAMETER PasswordableId
    Id of the asset to associate with the password

    .PARAMETER InPortal
    Display password in portal

    .PARAMETER Password
    Password

    .PARAMETER OTPSecret
    OTP secret

    .PARAMETER URL
    Url for the password

    .PARAMETER Username
    Username

    .PARAMETER Description
    Password description

    .PARAMETER PasswordType
    Password type

    .PARAMETER PasswordFolderId
    Id of requested password folder

    .PARAMETER Slug
    Url identifier

    .EXAMPLE
    Set-HuduPassword -Id 1 -CompanyId 1 -Password 'this_is_my_new_password'

    #>
    [CmdletBinding(SupportsShouldProcess)]
    # This will silence the warning for variables with Password in their name.
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingUsernameAndPasswordParams', '')]
    Param (
        [Parameter(Mandatory = $true)]
        [Int]$Id,

        [String]$Name,

        [Alias('company_id')]
        [Int]$CompanyId,

        [Alias('passwordable_type')]
        [String]$PasswordableType = '',

        [Alias('passwordable_id')]
        [int]$PasswordableId = '',

        [Alias('in_portal')]
        [Bool]$InPortal = $false,
        [String]$Password = '',

        [Alias('otp_secret')]
        [string]$OTPSecret = '',

        [String]$URL = '',

        [String]$Username = '',

        [String]$Description = '',

        [Alias('password_type')]
        [String]$PasswordType = '',

        [Alias('password_folder_id')]
        [int]$PasswordFolderId,

        [string]$Slug
    )

    $Object = Get-HuduPasswords -Id $Id 
    $AssetPassword = [ordered]@{asset_password = $Object }

    if ($Name) {
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name name -Force -Value $Name
        
    }
    
    if ($CompanyId) {
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name company_id -Force -Value $CompanyId
    }
    
    if ($Password) {
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name password -Force -Value $Password
    }
    
    if ($InPortal) {
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name in_portal -Force -Value $InPortal
    }
    

    if ($PasswordableType) {
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name passwordable_type -Force -Value $PasswordableType
    }
    if ($PasswordableId) {
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name passwordable_id -Force -Value $PasswordableId
    }

    if ($OTPSecret) {
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name otp_secret -Force -Value $OTPSecret
    }

    if ($URL) {
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name url -Force -Value $URL
    }

    if ($Username) {
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name username -Force -Value $Username
    }

    if ($Description) {
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name description -Force -Value $Description
    }

    if ($PasswordType) {
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name password_type -Force -Value $PasswordType
    }

    if ($PasswordFolderId) {
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name password_folder_id -Force -Value $PasswordFolderId
    }

    if ($Slug) {
        $AssetPassword.asset_password | Add-Member -MemberType NoteProperty -Name slug -Force -Value $Slug
    }

    $JSON = $AssetPassword | ConvertTo-Json -Depth 10

    if ($PSCmdlet.ShouldProcess($Id)) {
        Invoke-HuduRequest -Method put -Resource "/api/v1/asset_passwords/$Id" -Body $JSON
    }
}
#EndRegion './Public/Set-HuduPassword.ps1' 158
#Region './Public/Set-HuduPasswordArchive.ps1' -1

function Set-HuduPasswordArchive {
    <#
    .SYNOPSIS
    Archive/Unarchive a Password

    .DESCRIPTION
    Uses Hudu API to archive or unarchive a password

    .PARAMETER Id
    Id of the requested Password

    .PARAMETER Archive
    Boolean of archive status

    .EXAMPLE
    Set-HuduPasswordArchive -Archive $true -Id 1

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
        [Int]$Id,
        [Parameter(Mandatory = $true)]
        [Bool]$Archive
    )

    process {
        if ($Archive) {
            $Action = 'archive'
        } else {
            $Action = 'unarchive'
        }

        if ($PSCmdlet.ShouldProcess($Id)) {
            Invoke-HuduRequest -Method put -Resource "/api/v1/asset_passwords/$Id/$Action"
        }
    }
}
#EndRegion './Public/Set-HuduPasswordArchive.ps1' 39
#Region './Public/Set-HuduWebsite.ps1' -1

function Set-HuduWebsite {
    <#
    .SYNOPSIS
    Update a Website

    .DESCRIPTION
    Uses Hudu API to update a website

    .PARAMETER Id
    Id of requested website

    .PARAMETER Name
    Website name (e.g. https://example.com)

    .PARAMETER Notes
    Website Notes

    .PARAMETER Paused
    When true, website monitoring is paused.

    .PARAMETER CompanyId
    Used to associate website with company

    .PARAMETER DisableDNS
    When true, dns monitoring is paused.

    .PARAMETER DisableSSL
    When true, ssl cert monitoring is paused.

    .PARAMETER DisableWhois
    When true, whois monitoring is paused.

    .PARAMETER Slug
    Url identifier

    .EXAMPLE
    Set-HuduWebsite -Id 1 -Paused $true

    #>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true)]
        [Int]$Id,

        [Parameter(Mandatory = $true)]
        [String]$Name,

        [String]$Notes = '',

        [String]$Paused = '',

        [Alias('company_id')]
        [Parameter(Mandatory = $true)]
        [Int]$CompanyId,

        [Alias('disable_dns')]
        [String]$DisableDNS = '',

        [Alias('disable_ssl')]
        [String]$DisableSSL = '',

        [Alias('disable_whois')]
        [String]$DisableWhois = '',

        [string]$Slug
    )

    $Website = [ordered]@{website = [ordered]@{} }

    $Website.website.add('name', $Name)

    if ($Notes) {
        $Website.website.add('notes', $Notes)
    }

    if ($Paused) {
        $Website.website.add('paused', $Paused)
    }

    $Website.website.add('company_id', $companyid)

    if ($DisableDNS) {
        $Website.website.add('disable_dns', $DisableDNS)
    }

    if ($DisableSSL) {
        $Website.website.add('disable_ssl', $DisableSSL)
    }

    if ($DisableWhois) {
        $Website.website.add('disable_whois', $DisableWhois)
    }

    if ($Slug) {
        $Website.website.add('slug', $Slug)
    }

    $JSON = $Website | ConvertTo-Json

    if ($PSCmdlet.ShouldProcess($Id)) {
        Invoke-HuduRequest -Method put -Resource "/api/v1/websites/$Id" -Body $JSON
    }
}
#EndRegion './Public/Set-HuduWebsite.ps1' 104

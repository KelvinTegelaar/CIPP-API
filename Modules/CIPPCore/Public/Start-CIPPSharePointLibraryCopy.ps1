function Start-CIPPSharePointLibraryCopy {
    <#
    .SYNOPSIS
        Preflights or starts a SharePoint library-to-library copy operation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('PreflightLibraryCopy', 'StartLibraryCopy')]
        [string]$Mode,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$SourceSiteId,

        [string]$SourceSiteUrl,
        [Parameter(Mandatory = $true)]
        [string]$SourceListId,
        [string]$SourceSiteName,
        [string]$SourceLibraryName,

        [Parameter(Mandatory = $true)]
        [string]$DestSiteId,

        [string]$DestSiteUrl,
        [Parameter(Mandatory = $true)]
        [string]$DestListId,
        [string]$DestSiteName,
        [string]$DestLibraryName,

        [int]$NameConflictBehavior = 1,
        [string]$StartedBy,
        $Headers,
        $APIName = 'SharePoint Library Copy'
    )

    $ResolveLibraryMeta = {
        param([string]$SiteId, [string]$SiteUrl, [string]$ListId)
        if ([string]::IsNullOrWhiteSpace($SiteId)) {
            if ([string]::IsNullOrWhiteSpace($SiteUrl)) {
                throw 'SourceSiteId or SourceSiteUrl is required.'
            }
            $ParsedUrl = [System.Uri]$SiteUrl
            $SiteSegment = if ($ParsedUrl.AbsolutePath -in @('', '/')) {
                $ParsedUrl.Host
            } else {
                "$($ParsedUrl.Host):$($ParsedUrl.AbsolutePath):"
            }
            $SiteMeta = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/$SiteSegment`?`$select=id,webUrl,displayName" -tenantid $TenantFilter -asapp $true
            $SiteId = $SiteMeta.id
            $SiteUrl = $SiteMeta.webUrl
        } else {
            $SiteMeta = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/$SiteId`?`$select=id,webUrl,displayName" -tenantid $TenantFilter -asapp $true
            if (-not $SiteUrl) { $SiteUrl = $SiteMeta.webUrl }
        }
        $List = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/$SiteId/lists/$ListId`?`$select=id,displayName,name,list" -tenantid $TenantFilter -asapp $true
        [PSCustomObject]@{
            SiteId          = $SiteId
            SiteUrl         = $SiteUrl
            SiteDisplayName = $SiteMeta.displayName
            ListId          = $List.id
            Title           = $List.displayName
            Name            = $List.name
            Template        = $List.list.template
        }
    }

    $SourceMeta = & $ResolveLibraryMeta -SiteId $SourceSiteId -SiteUrl $SourceSiteUrl -ListId $SourceListId
    $DestMeta = & $ResolveLibraryMeta -SiteId $DestSiteId -SiteUrl $DestSiteUrl -ListId $DestListId

    foreach ($Meta in @($SourceMeta, $DestMeta)) {
        $Eligible = Test-CIPPSharePointLibraryCopyEligible -Template $Meta.Template -Title $Meta.Title -Name $Meta.Name
        if (-not $Eligible.Eligible) {
            throw $Eligible.Reason
        }
    }

    if ($SourceMeta.SiteId -eq $DestMeta.SiteId -and $SourceMeta.ListId -eq $DestMeta.ListId) {
        throw 'Source and destination library must be different.'
    }

    $Enumerate = Get-CIPPSharePointLibraryRootChildUris -TenantFilter $TenantFilter -SiteId $SourceMeta.SiteId `
        -SiteUrl $SourceMeta.SiteUrl -ListId $SourceMeta.ListId

    $Count = $Enumerate.EligibleRootCount
    if ($Count -eq 0) {
        throw 'Source library has no eligible content to copy.'
    }
    if ($Count -gt 1000) {
        throw "Source library has $Count eligible root items (limit 1,000). Group files into folders and try again."
    }

    $WarnLevel = 'none'
    if ($Count -gt 200) { $WarnLevel = 'strong' }
    elseif ($Count -gt 50) { $WarnLevel = 'soft' }

    if ($Mode -eq 'PreflightLibraryCopy') {
        return [PSCustomObject]@{
            EligibleRootCount = $Count
            WarnLevel         = $WarnLevel
            Message           = "Estimated SharePoint jobs: $Count."
        }
    }

    $SourceRoot = Resolve-CIPPSharePointLibraryRootUri -TenantFilter $TenantFilter -SiteUrl $SourceMeta.SiteUrl `
        -SiteId $SourceMeta.SiteId -ListId $SourceMeta.ListId
    $DestRoot = Resolve-CIPPSharePointLibraryRootUri -TenantFilter $TenantFilter -SiteUrl $DestMeta.SiteUrl `
        -SiteId $DestMeta.SiteId -ListId $DestMeta.ListId

    $SameWeb = $SourceMeta.SiteId -eq $DestMeta.SiteId
    $CopyJobs = Invoke-CIPPSharePointCreateCopyJobs -TenantFilter $TenantFilter -SourceSiteUrl $SourceRoot.SiteUrl `
        -ExportObjectUris $Enumerate.ChildUris -DestinationUri $DestRoot.LibraryRootUri `
        -NameConflictBehavior $NameConflictBehavior -SameWebCopyMoveOptimization $SameWeb

    $OperationId = (New-Guid).Guid
    $Expiry = ([DateTime]::UtcNow.AddDays(7)).ToString('o')
    $SrcSiteName = if ($SourceSiteName) { $SourceSiteName } else { $SourceMeta.SiteDisplayName ?? 'Source site' }
    $SrcLibName = if ($SourceLibraryName) { $SourceLibraryName } else { $SourceMeta.Title }
    $DstSiteName = if ($DestSiteName) { $DestSiteName } else { $DestMeta.SiteDisplayName ?? 'Destination site' }
    $DstLibName = if ($DestLibraryName) { $DestLibraryName } else { $DestMeta.Title }

    $HandleStates = @($CopyJobs | ForEach-Object {
            [PSCustomObject]@{ Status = 'Queued'; IsComplete = $false }
        })

    Set-CIPPSharePointLibraryCopyOperation -TenantFilter $TenantFilter -OperationId $OperationId -Entity @{
        SourceSiteUrl     = $SourceRoot.SiteUrl
        SourceSiteName    = $SrcSiteName
        SourceLibraryName = $SrcLibName
        DestSiteName      = $DstSiteName
        DestLibraryName   = $DstLibName
        StartedBy         = $StartedBy
        Status            = 'Processing'
        JobHandleCount    = $CopyJobs.Count
        Expiry            = $Expiry
        CopyJobInfos      = @($CopyJobs)
        HandleStates      = (ConvertTo-Json -InputObject @($HandleStates) -Compress -Depth 4)
        SanitizedSnapshot = (ConvertTo-Json -InputObject @{
                OperationId   = $OperationId
                Status        = 'Processing'
                JobsComplete  = 0
                JobsTotal     = $CopyJobs.Count
                TotalErrors   = 0
                TotalWarnings = 0
                Message       = 'Copy queued.'
            } -Compress)
    }

    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter `
        -message "Started library copy $OperationId ($SrcLibName -> $DstLibName, $($CopyJobs.Count) jobs)" -sev Info

    [PSCustomObject]@{
        OperationId     = $OperationId
        JobHandleCount  = $CopyJobs.Count
        Message         = 'Library copy started.'
    }
}

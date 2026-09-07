function Invoke-ExecSiteBrowserLibraryCopy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    .DESCRIPTION
        Starts or preflights a SharePoint document library content copy (CreateCopyJobs + MoveButKeepSource).
        Actions: PreflightLibraryCopy, StartLibraryCopy.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter ?? $Request.Body.TenantFilter
    $Action = $Request.Body.Action ?? $Request.Query.Action
    $StatusCode = [HttpStatusCode]::OK

    try {
        if ([string]::IsNullOrWhiteSpace($TenantFilter)) { throw 'tenantFilter is required.' }
        if ([string]::IsNullOrWhiteSpace($Action)) { throw 'Action is required.' }
        if ($Action -notin @('PreflightLibraryCopy', 'StartLibraryCopy')) {
            throw "Unknown Action '$Action'. Supported: PreflightLibraryCopy, StartLibraryCopy."
        }

        $User = try {
            [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json
        } catch { $null }
        $StartedBy = $User.userDetails ?? $Headers.'x-ms-client-principal-name' ?? 'CIPP-API'

        $ConflictRaw = $Request.Body.NameConflictBehavior ?? $Request.Body.nameConflictBehavior ?? 'Replace'
        $NameConflictBehavior = switch ([string]$ConflictRaw) {
            'Fail' { 0 }
            'Replace' { 1 }
            default { [int]$ConflictRaw }
        }

        $Params = @{
            Mode              = $Action
            TenantFilter      = $TenantFilter
            SourceSiteId      = [string]($Request.Body.SourceSiteId ?? $Request.Body.sourceSiteId)
            SourceSiteUrl     = [string]($Request.Body.SourceSiteUrl ?? $Request.Body.sourceSiteUrl)
            SourceListId      = [string]($Request.Body.SourceListId ?? $Request.Body.sourceListId)
            SourceSiteName    = [string]($Request.Body.SourceSiteName ?? $Request.Body.sourceSiteName)
            SourceLibraryName = [string]($Request.Body.SourceLibraryName ?? $Request.Body.sourceLibraryName)
            DestSiteId        = [string]($Request.Body.DestSiteId ?? $Request.Body.destSiteId)
            DestSiteUrl       = [string]($Request.Body.DestSiteUrl ?? $Request.Body.destSiteUrl)
            DestListId        = [string]($Request.Body.DestListId ?? $Request.Body.destListId)
            DestSiteName      = [string]($Request.Body.DestSiteName ?? $Request.Body.destSiteName)
            DestLibraryName   = [string]($Request.Body.DestLibraryName ?? $Request.Body.destLibraryName)
            NameConflictBehavior = $NameConflictBehavior
            StartedBy         = $StartedBy
            Headers           = $Headers
            APIName           = $APIName
        }

        if ([string]::IsNullOrWhiteSpace($Params.SourceListId)) { throw 'SourceListId is required.' }
        if ([string]::IsNullOrWhiteSpace($Params.DestListId)) { throw 'DestListId is required.' }
        if ([string]::IsNullOrWhiteSpace($Params.SourceSiteId) -and [string]::IsNullOrWhiteSpace($Params.SourceSiteUrl)) {
            throw 'SourceSiteId or SourceSiteUrl is required.'
        }
        if ([string]::IsNullOrWhiteSpace($Params.DestSiteId) -and [string]::IsNullOrWhiteSpace($Params.DestSiteUrl)) {
            throw 'DestSiteId or DestSiteUrl is required.'
        }

        $Result = Start-CIPPSharePointLibraryCopy @Params
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message "Library copy action $Action completed." -sev Info
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to run Action '$Action'. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}

function Invoke-CIPPSharePointCreateCopyJobs {
    <#
    .SYNOPSIS
        Submits a CreateCopyJobs request on the source SharePoint site.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$SourceSiteUrl,

        [Parameter(Mandatory = $true)]
        [string[]]$ExportObjectUris,

        [Parameter(Mandatory = $true)]
        [string]$DestinationUri,

        [int]$NameConflictBehavior = 1,
        [bool]$SameWebCopyMoveOptimization = $false
    )

    $SharePointInfo = Get-SharePointAdminLink -Public $false -tenantFilter $TenantFilter
    $Scope = "$($SharePointInfo.SharePointUrl)/.default"

    $Body = ConvertTo-Json -InputObject @{
        exportObjectUris = @($ExportObjectUris)
        destinationUri   = $DestinationUri
        options          = @{
            IsMoveMode                            = $false
            MoveButKeepSource                     = $true
            IgnoreVersionHistory                  = $false
            AllowSchemaMismatch                   = $true
            AllowSmallerVersionLimitOnDestination = $true
            NameConflictBehavior                  = $NameConflictBehavior
            BypassSharedLock                      = $true
            SameWebCopyMoveOptimization           = $SameWebCopyMoveOptimization
            ExcludeChildren                       = $false
        }
    } -Depth 6 -Compress

    $Uri = "$($SourceSiteUrl.TrimEnd('/'))/_api/site/CreateCopyJobs"
    $Response = New-GraphPOSTRequest -uri $Uri -tenantid $TenantFilter -scope $Scope -type POST -body $Body `
        -AddedHeaders @{ Accept = 'application/json;odata=verbose' } `
        -contentType 'application/json;odata=verbose' -UseCertificate -AsApp $true

    if ($Response -is [string]) {
        $Response = $Response | ConvertFrom-Json
    }

    $Jobs = @()
    if ($Response.d -and $Response.d.CreateCopyJobs) {
        $CreateCopyJobs = $Response.d.CreateCopyJobs
        $Jobs = if ($null -ne $CreateCopyJobs.results) { @($CreateCopyJobs.results) } else { @($CreateCopyJobs) }
    } elseif ($Response.value) {
        $Jobs = @($Response.value)
    } elseif ($Response -is [System.Array]) {
        $Jobs = @($Response)
    } elseif ($Response.d -and ($Response.d.JobId -or $Response.d.jobId)) {
        $Jobs = @($Response.d)
    } elseif ($Response.JobId -or $Response.jobId) {
        $Jobs = @($Response)
    }

    if ($Jobs.Count -eq 0) {
        throw 'SharePoint CreateCopyJobs returned no job handles.'
    }

    # Normalize to the three fields GetCopyJobProgress needs (strip SourceListItemUniqueIds / OData wrappers).
    return @($Jobs | ForEach-Object {
            $Candidate = $_
            if ($null -ne $_.results) {
                $Nested = @($_.results)
                if ($Nested.Count -eq 1 -and ($Nested[0].JobId -or $Nested[0].jobId)) {
                    $Candidate = $Nested[0]
                }
            }

            $JobId = [string]($Candidate.JobId ?? $Candidate.jobId ?? $Candidate.JobID ?? '')
            $JobQueueUri = $Candidate.JobQueueUri ?? $Candidate.jobQueueUri
            if ($JobQueueUri -is [PSCustomObject]) {
                $JobQueueUri = [string]($JobQueueUri.Url ?? $JobQueueUri.AbsoluteUri ?? $JobQueueUri)
            }
            $EncryptionKey = $Candidate.EncryptionKey ?? $Candidate.encryptionKey
            if ($EncryptionKey -is [PSCustomObject]) {
                $EncryptionKey = $EncryptionKey.'#text' ?? $EncryptionKey.Value ?? $EncryptionKey.bytes
            }

            if ([string]::IsNullOrWhiteSpace($JobId) -or [string]::IsNullOrWhiteSpace([string]$JobQueueUri)) {
                throw 'SharePoint CreateCopyJobs returned a handle without JobId or JobQueueUri.'
            }

            [PSCustomObject]@{
                JobId         = $JobId
                JobQueueUri   = [string]$JobQueueUri
                EncryptionKey = $EncryptionKey
            }
        })
}

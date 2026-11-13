function Invoke-ExecEmptySiteRecycleBin {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.SiteRecycleBin.ReadWrite
    .DESCRIPTION
        Permanently empty a site recycle bin (first stage, second stage, or both).
        Item ids are used only server-side; the response never includes file names.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter ?? $Request.Body.TenantFilter
    $SiteUrl = $Request.Body.SiteUrl
    $Stage = [string]($Request.Body.Stage ?? 'Both')

    if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'tenantFilter is required.' } })
    }
    if ([string]::IsNullOrWhiteSpace($SiteUrl)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'SiteUrl is required.' } })
    }
    if ($Stage -notin @('First', 'Second', 'Both')) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = "Invalid Stage '$Stage'. Valid values: First, Second, Both." }
            })
    }

    try {
        $RestContext = Resolve-CIPPSharePointRestContext -TenantFilter $TenantFilter -SiteUrl $SiteUrl
        $Scope = $RestContext.Scope
        $JsonAccept = $RestContext.Headers
        $BaseUri = $RestContext.BaseUri
        $DeletedCount = 0
        $Errors = [System.Collections.Generic.List[string]]::new()

        function Invoke-CIPPRecycleDeleteAll {
            param([string]$Uri)
            $null = New-GraphPostRequest -uri $Uri -tenantid $TenantFilter -scope $Scope -type POST -body '{}' -contentType 'application/json;odata=nometadata' -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
        }

        function Invoke-CIPPRecycleDeleteByIdsBatch {
            param(
                [ValidateSet('First', 'Second')]
                [string]$TargetStage
            )
            # The recycle bin query returns no next link, so ask SharePoint for this stage only and
            # read from the top again after each delete until the stage is empty.
            $StateFilter = if ($TargetStage -eq 'Second') { 2 } else { 1 }
            $ListUri = "$BaseUri/site/RecycleBin?`$select=Id&`$filter=ItemState eq $StateFilter&`$top=100"
            $Submitted = [System.Collections.Generic.HashSet[string]]::new()
            $BatchDeleted = 0
            $Guard = 0
            while ($Guard -lt 200) {
                $Guard++
                $Page = New-GraphGetRequest -uri $ListUri -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true -noPagination $true -SkipValueExtraction
                $Ids = [System.Collections.Generic.List[string]]::new()
                foreach ($Item in @($Page.value)) {
                    if (-not $Item.Id) { continue }
                    $Id = [string]$Item.Id
                    # An id we already sent is still there: SharePoint accepted the delete and did not act on it.
                    if ($Submitted.Contains($Id)) {
                        throw "SharePoint did not delete the $($TargetStage.ToLower())-stage items it accepted for deletion ($BatchDeleted deleted before that)."
                    }
                    $Ids.Add($Id)
                }
                if ($Ids.Count -eq 0) { return $BatchDeleted }
                for ($i = 0; $i -lt $Ids.Count; $i += 25) {
                    $Chunk = @($Ids[$i..([Math]::Min($i + 24, $Ids.Count - 1))])
                    $DeleteBody = ConvertTo-Json -Compress -Depth 5 -InputObject @{ ids = @($Chunk) }
                    $null = New-GraphPostRequest -uri "$BaseUri/site/RecycleBin/DeleteByIds" -tenantid $TenantFilter -scope $Scope -type POST -body $DeleteBody -contentType 'application/json;odata=nometadata' -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
                    foreach ($Id in $Chunk) { $null = $Submitted.Add($Id) }
                    $BatchDeleted = $BatchDeleted + $Chunk.Count
                }
            }
            throw "Stopped after deleting $BatchDeleted $($TargetStage.ToLower())-stage items. Run the cleanup again to continue."
        }

        $FirstStageDeleted = 0
        if ($Stage -in @('First', 'Both')) {
            # Not web/RecycleBin/deleteAll(): for the app-only caller it returns success and leaves the
            # items other users deleted in place, so delete first-stage items by id from the site collection bin.
            try {
                $FirstStageDeleted = Invoke-CIPPRecycleDeleteByIdsBatch -TargetStage First
                $DeletedCount = $DeletedCount + $FirstStageDeleted
            } catch {
                $Errors.Add("First stage: $($_.Exception.Message)")
            }
        }

        if ($Stage -in @('Second', 'Both')) {
            try {
                Invoke-CIPPRecycleDeleteAll -Uri "$BaseUri/site/RecycleBin/deleteAllSecondStageItems"
                $DeletedCount += 1
            } catch {
                try {
                    Invoke-CIPPRecycleDeleteAll -Uri "$BaseUri/site/RecycleBin/deleteAll()"
                    $DeletedCount += 1
                } catch {
                    try {
                        $DeletedCount += Invoke-CIPPRecycleDeleteByIdsBatch -TargetStage Second
                    } catch {
                        $Errors.Add("Second stage: $($_.Exception.Message)")
                    }
                }
            }
        }

        if ($Errors.Count -gt 0 -and $DeletedCount -eq 0) {
            throw ($Errors -join '; ')
        }

        $Results = "Emptied recycle bin ($Stage) for $SiteUrl."
        if ($Stage -in @('First', 'Both') -and $Errors.Count -eq 0) {
            $Results = "$Results Deleted $FirstStageDeleted first-stage item(s)."
        }
        if ($Errors.Count -gt 0) {
            $Results += " Partial warnings: $($Errors -join '; ')"
        }
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Info
        $StatusCode = Get-CippBulkStatusCode -Total ($Stage -eq 'Both' ? 2 : 1) -Failed $Errors.Count
        $Body = @{ Results = $Results; deletedAttempts = $DeletedCount }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to empty recycle bin on $($SiteUrl): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Body = @{ Results = $Results }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

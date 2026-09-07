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

    try {
        if ([string]::IsNullOrWhiteSpace($TenantFilter)) { throw 'tenantFilter is required.' }
        if ([string]::IsNullOrWhiteSpace($SiteUrl)) { throw 'SiteUrl is required.' }
        if ($Stage -notin @('First', 'Second', 'Both')) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = "Invalid Stage '$Stage'. Valid values: First, Second, Both." }
                })
        }

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
            $StateFilter = if ($TargetStage -eq 'Second') { 2 } else { 1 }
            $BatchDeleted = 0
            $NextUri = "$BaseUri/site/RecycleBin?`$select=Id,ItemState&`$top=100&`$orderby=DeletedDate desc"
            $Guard = 0
            while ($NextUri -and $Guard -lt 200) {
                $Guard++
                $Page = New-GraphGetRequest -uri $NextUri -tenantid $TenantFilter -scope $Scope -extraHeaders $JsonAccept -UseCertificate -AsApp $true -noPagination $true -SkipValueExtraction
                $Items = @($Page.value)
                $NextLink = $Page.'@odata.nextLink'
                $Ids = @(
                    foreach ($Item in $Items) {
                        $State = 0
                        try { $State = [int]$Item.ItemState } catch { $State = 0 }
                        if ($State -eq $StateFilter -and $Item.Id) { [string]$Item.Id }
                    }
                )
                if ($Ids.Count -eq 0) {
                    if ([string]::IsNullOrWhiteSpace($NextLink)) { break }
                    $NextUri = $NextLink
                    continue
                }
                for ($i = 0; $i -lt $Ids.Count; $i += 25) {
                    $Chunk = @($Ids[$i..([Math]::Min($i + 24, $Ids.Count - 1))])
                    $DeleteBody = ConvertTo-Json -Compress -Depth 5 -InputObject @{ ids = @($Chunk) }
                    $null = New-GraphPostRequest -uri "$BaseUri/site/RecycleBin/DeleteByIds" -tenantid $TenantFilter -scope $Scope -type POST -body $DeleteBody -contentType 'application/json;odata=nometadata' -AddedHeaders $JsonAccept -UseCertificate -AsApp $true
                    $BatchDeleted += $Chunk.Count
                }
                # After deletes, restart from the first page so we do not skip items when the list shifts.
                $NextUri = "$BaseUri/site/RecycleBin?`$select=Id,ItemState&`$top=100&`$orderby=DeletedDate desc"
            }
            return $BatchDeleted
        }

        if ($Stage -in @('First', 'Both')) {
            try {
                Invoke-CIPPRecycleDeleteAll -Uri "$BaseUri/web/RecycleBin/deleteAll()"
                $DeletedCount += 1 # deleteAll does not return a count; mark attempt
            } catch {
                try {
                    $DeletedCount += Invoke-CIPPRecycleDeleteByIdsBatch -TargetStage First
                } catch {
                    $Errors.Add("First stage: $($_.Exception.Message)")
                }
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
        if ($Errors.Count -gt 0) {
            $Results += " Partial warnings: $($Errors -join '; ')"
        }
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Info
        $StatusCode = [HttpStatusCode]::OK
        $Body = @{ Results = $Results; deletedAttempts = $DeletedCount }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to empty recycle bin on $($SiteUrl): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
        $Body = @{ Results = $Results }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

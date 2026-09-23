function Invoke-ExecBECEvidenceExport {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    .SYNOPSIS
        Builds the evidence package for a Business Email Compromise run and returns it.
    .DESCRIPTION
        Collates the run's stored results, one CSV per finding set, the score, the containment history, every logbook entry stamped with the case id and the browser-rendered PDF reports (pdfBase64, pdfSummaryBase64) into a ZIP. Nothing is stored: the ZIP is returned base64-encoded (ZipBase64) for the browser to save. Metadata only - nothing in the package is message content.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $CaseId = [string]$Request.Body.caseId
    # optional: the report PDFs rendered in the browser, base64-encoded (full report + C-suite summary)
    $PdfBase64 = [string]$Request.Body.pdfBase64
    $PdfSummaryBase64 = [string]$Request.Body.pdfSummaryBase64

    Set-CippBecCaseContext -CaseId $CaseId
    try {
        if (-not $TenantFilter) { throw 'tenantFilter is required' }
        if (-not $CaseId) { throw 'caseId is required' }
        $Package = New-CIPPBecEvidencePackage -TenantFilter $TenantFilter -CaseId $CaseId -PdfBase64 $PdfBase64 -PdfSummaryBase64 $PdfSummaryBase64 -Headers $Headers -APIName $APIName
        $Body = @{
            Results  = "Evidence package for case $CaseId created: $($Package.FileCount) files, $([math]::Round($Package.Bytes / 1KB)) KB"
            Evidence = [pscustomobject]@{
                CaseId    = $Package.CaseId
                Bytes     = $Package.Bytes
                FileCount = $Package.FileCount
                ZipBase64 = [System.Convert]::ToBase64String($Package.ZipBytes)
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Evidence export for BEC case $CaseId failed: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = @{ Results = "Evidence export failed: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    } finally {
        Set-CippBecCaseContext -CaseId $null
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

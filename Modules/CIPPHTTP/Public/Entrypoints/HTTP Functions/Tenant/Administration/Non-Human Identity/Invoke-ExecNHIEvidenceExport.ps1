function Invoke-ExecNHIEvidenceExport {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.Read
    .SYNOPSIS
        Exports the evidence package of a non-human identity (NHI) compromise case.
    .DESCRIPTION
        Collates the run's stored results, one CSV per finding set, the score, the containment history and every logbook entry stamped with the case id into a ZIP. Nothing is stored: the ZIP is returned base64-encoded (ZipBase64) for the browser to save. Metadata only.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $CaseId = [string]$Request.Body.caseId

    Set-CippBecCaseContext -CaseId $CaseId
    try {
        if (-not $TenantFilter) { throw 'tenantFilter is required' }
        if (-not $CaseId) { throw 'caseId is required' }
        $Package = New-CIPPBecEvidencePackage -Kind 'NHI' -TenantFilter $TenantFilter -CaseId $CaseId -Headers $Headers -APIName $APIName
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
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Evidence export for NHI case $CaseId failed: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
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

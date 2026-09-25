function Invoke-ListCAGapAnalysis {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.SecuritySimulations.Read
    .DESCRIPTION
        Conditional Access gap analysis for one tenant from the cached policies: findings, the
        persona-by-control coverage matrix and the 1 to 10 posture score.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    try {
        $TenantFilter = $Request.Query.tenantFilter
        if (-not $TenantFilter -or $TenantFilter -in @('AllTenants', 'allTenants')) { throw 'Select a single tenant for the Conditional Access gap analysis.' }

        $Licensed = Test-CIPPStandardLicense -StandardName 'ConditionalAccessCache' -TenantFilter $TenantFilter -Preset Entra -SkipLog
        $Analysis = $null
        $AnalysisError = $null
        if ($Licensed -ne $false) {
            try {
                $Analysis = Get-CIPPCAGapAnalysis -TenantFilter $TenantFilter
            } catch {
                $AnalysisError = $_.Exception.Message
            }
        }

        $Results = [PSCustomObject]@{
            tenantFilter  = $TenantFilter
            licensed      = $Licensed -ne $false
            analysis      = $Analysis
            analysisError = $AnalysisError
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Failed to run the Conditional Access gap analysis: $($_.Exception.Message)" -Sev 'Error'
        $Results = @{ Results = "Failed to run the Conditional Access gap analysis: $($_.Exception.Message)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Results
        })
}

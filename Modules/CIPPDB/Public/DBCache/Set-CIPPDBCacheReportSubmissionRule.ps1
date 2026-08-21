function Set-CIPPDBCacheReportSubmissionRule {
    <#
    .SYNOPSIS
        Caches Exchange Online report submission rules

    .PARAMETER TenantFilter
        The tenant to cache report submission rule data for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Exchange report submission rules' -sev Debug

        $ReportSubmissionRules = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-ReportSubmissionRule'
        if ($ReportSubmissionRules) {
            $ReportSubmissionRuleArray = @($ReportSubmissionRules)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ReportSubmissionRule' -Data $ReportSubmissionRuleArray -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($ReportSubmissionRuleArray.Count) report submission rules" -sev Debug
        }
        $ReportSubmissionRules = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache report submission rule data: $($_.Exception.Message)" -sev Error
    }
}

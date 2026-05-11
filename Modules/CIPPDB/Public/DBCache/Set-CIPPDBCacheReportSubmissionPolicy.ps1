function Set-CIPPDBCacheReportSubmissionPolicy {
    <#
    .SYNOPSIS
        Caches Defender Report Submission Policies

    .DESCRIPTION
        Calls Get-ReportSubmissionPolicy via New-ExoRequest and writes the
        result into the CippReportingDB under Type 'ReportSubmissionPolicy'.
        Used by CIS test 8.6.1 (security reporting destinations).

    .PARAMETER TenantFilter
        The tenant to cache the report submission policies for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Report Submission Policies' -sev Debug

        $ReportSubmissionPolicies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-ReportSubmissionPolicy'

        if ($ReportSubmissionPolicies) {
            $Data = @($ReportSubmissionPolicies)
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ReportSubmissionPolicy' -Data $Data
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'ReportSubmissionPolicy' -Data $Data -Count
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Data.Count) Report Submission Policies" -sev Debug
        }
        $ReportSubmissionPolicies = $null

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Report Submission Policies: $($_.Exception.Message)" -sev Error
    }
}

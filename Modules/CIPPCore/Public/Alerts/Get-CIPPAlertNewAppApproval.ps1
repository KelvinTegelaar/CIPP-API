
function Get-CIPPAlertNewAppApproval {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        $input,
        $TenantFilter
    )
    try {
        $Approvals = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/identityGovernance/appConsent/appConsentRequests' -tenantid $TenantFilter | Where-Object -Property requestStatus -EQ 'inProgress'
        if ($Approvals.count -gt 1) {
            Write-AlertMessage -tenant $($TenantFilter) -message "There is are $($Approvals.count) App Approvals waiting."
        }
    } catch {
    }
}


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
            "There are $($Approvals.count) App Approval(s) pending."
        }
    } catch {
    }
}

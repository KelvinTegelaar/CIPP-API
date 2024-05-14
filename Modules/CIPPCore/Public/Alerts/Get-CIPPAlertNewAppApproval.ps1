
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
            $AlertData = "There are $($Approvals.count) App Approval(s) pending."
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
    }
}

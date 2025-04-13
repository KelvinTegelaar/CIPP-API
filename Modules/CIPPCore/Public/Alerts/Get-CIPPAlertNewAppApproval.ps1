
function Get-CIPPAlertNewAppApproval {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter,
        $Headers
    )
    try {
        $Approvals = New-GraphGetRequest -Uri "https://graph.microsoft.com/v1.0/identityGovernance/appConsent/appConsentRequests?`$filter=userConsentRequests/any (u:u/status eq 'InProgress')" -tenantid $TenantFilter
        if ($Approvals.count -gt 0) {
            $AlertData = "There are $($Approvals.count) App Approval(s) pending."
            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
    }
}

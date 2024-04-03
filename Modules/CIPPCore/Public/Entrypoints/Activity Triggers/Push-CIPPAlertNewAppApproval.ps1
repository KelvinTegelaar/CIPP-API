
function Push-CIPPAlertNewAppApproval {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Item
    )
    try {
        $Approvals = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/identityGovernance/appConsent/appConsentRequests' -tenantid $item.tenant
        if ($Approvals.count -gt 1) {
            Write-AlertMessage -tenant $($Item.tenant) -message "There is are $($Approvals.count) App Approvals waiting."
        }
    } catch {
    }
}

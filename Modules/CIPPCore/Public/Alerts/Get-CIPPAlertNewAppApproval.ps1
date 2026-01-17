
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
        $Approvals = New-GraphGetRequest -Uri "https://graph.microsoft.com/beta/identityGovernance/appConsent/appConsentRequests?`$top=100&`$filter=userConsentRequests/any (u:u/status eq 'InProgress')" -tenantid $TenantFilter

        if ($Approvals.count -gt 0) {
            $TenantGUID = (Get-Tenants -TenantFilter $TenantFilter -SkipDomains).customerId
            $AlertData = [System.Collections.Generic.List[PSCustomObject]]::new()

            foreach ($App in $Approvals) {
                $userConsentRequests = New-GraphGetRequest -Uri "https://graph.microsoft.com/v1.0/identityGovernance/appConsent/appConsentRequests/$($App.id)/userConsentRequests" -tenantid $TenantFilter

                $userConsentRequests | ForEach-Object {
                    $consentUrl = if ($App.consentType -eq 'Static') {
                        # if something is going wrong here you've probably stumbled on a fourth variation - rvdwegen
                        "https://login.microsoftonline.com/$($TenantFilter)/adminConsent?client_id=$($App.appId)&bf_id=$($App.id)&redirect_uri=https://entra.microsoft.com/TokenAuthorize"
                    } elseif ($App.pendingScopes.displayName) {
                        "https://login.microsoftonline.com/$($TenantFilter)/v2.0/adminConsent?client_id=$($App.appId)&scope=$($App.pendingScopes.displayName -Join(' '))&bf_id=$($App.id)&redirect_uri=https://entra.microsoft.com/TokenAuthorize"
                    } else {
                        "https://login.microsoftonline.com/$($TenantFilter)/adminConsent?client_id=$($App.appId)&bf_id=$($App.id)&redirect_uri=https://entra.microsoft.com/TokenAuthorize"
                    }

                    $Message = [PSCustomObject]@{
                        RequestId   = $_.id
                        AppName     = $App.appDisplayName
                        RequestUser = $_.createdBy.user.userPrincipalName
                        Reason      = $_.reason
                        RequestDate = $_.createdDateTime
                        Status      = $_.status # Will always be InProgress as we filter to only get these but this will reduce confusion when an alert is generated
                        AppId       = $App.appId
                        Scopes      = ($App.pendingScopes.displayName -join ', ')
                        ConsentURL  = $consentUrl
                        Tenant      = $TenantFilter
                        TenantId    = $TenantGUID
                    }
                    $AlertData.Add($Message)
                }
            }

            Write-AlertTrace -cmdletName $MyInvocation.MyCommand -tenantFilter $TenantFilter -data $AlertData
        }
    } catch {
    }
}

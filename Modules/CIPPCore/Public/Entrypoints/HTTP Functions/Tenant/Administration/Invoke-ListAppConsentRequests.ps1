using namespace System.Net

function Invoke-ListAppConsentRequests {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Administration.Read
    #>
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter

    try {
        if ($TenantFilter -eq 'AllTenants') {
            throw 'AllTenants is not yet supported'
        }

        $appConsentRequests = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/identityGovernance/appConsent/appConsentRequests' -tenantid $TenantFilter # Need the beta endpoint to get consentType
        $Results = foreach ($app in $appConsentRequests) {
            $userConsentRequests = New-GraphGetRequest -Uri "https://graph.microsoft.com/v1.0/identityGovernance/appConsent/appConsentRequests/$($app.id)/userConsentRequests" -tenantid $TenantFilter
            $userConsentRequests | ForEach-Object {
                [pscustomobject]@{
                    appId                 = $app.appId
                    appDisplayName        = $app.appDisplayName
                    requestUser           = $_.createdBy.user.userPrincipalName
                    requestReason         = $_.reason
                    requestDate           = $_.createdDateTime
                    requestStatus         = $_.status
                    reviewedBy            = $_.approval.stages.reviewedBy.userPrincipalName
                    reviewedJustification = $_.approval.stages.justification
                    reviewedDate          = $_.approval.stages.reviewedDateTime
                    reviewedStatus        = $_.approval.stages.status
                    scopes                = $app.pendingScopes.displayName
                    consentUrl            = if ($app.consentType -eq 'Static') {
                        # if something is going wrong here you've probably stumbled on a fourth variation - rvdwegen
                        "https://login.microsoftonline.com/$($TenantFilter)/adminConsent?client_id=$($app.appId)&bf_id=$($app.id)&redirect_uri=https://entra.microsoft.com/TokenAuthorize"
                    } elseif ($app.pendingScopes.displayName) {
                        "https://login.microsoftonline.com/$($TenantFilter)/v2.0/adminConsent?client_id=$($app.appId)&scope=$($app.pendingScopes.displayName -Join(' '))&bf_id=$($app.id)&redirect_uri=https://entra.microsoft.com/TokenAuthorize"
                    } else {
                        "https://login.microsoftonline.com/$($TenantFilter)/adminConsent?client_id=$($app.appId)&bf_id=$($app.id)&redirect_uri=https://entra.microsoft.com/TokenAuthorize"
                    }
                }
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $StatusCode = [HttpStatusCode]::InternalServerError
        Write-LogMessage -Headers $Headers -API $APIName -message 'app consent request list failed' -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        $Results = @{ appDisplayName = "Error: $($ErrorMessage.NormalizedError)" }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })
}

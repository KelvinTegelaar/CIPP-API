using namespace System.Net

function Invoke-ListAppConsentRequests {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $TenantFilter = $Request.Query.TenantFilter
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    
    try {
        if ($Request.Query.TenantFilter -eq 'AllTenants') {
            throw 'AllTenants is not yet supported'
        } else {
            $TenantFilter = $Request.Query.TenantFilter
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
        $StatusCode = [HttpStatusCode]::OK
        Write-LogMessage -user $ExecutingUser -API $APIName -message 'app consent request list failed' -Sev 'Error' -tenant $TenantFilter
        $Results = @{ appDisplayName = "Error: $($_.Exception.Message)" }
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })
}
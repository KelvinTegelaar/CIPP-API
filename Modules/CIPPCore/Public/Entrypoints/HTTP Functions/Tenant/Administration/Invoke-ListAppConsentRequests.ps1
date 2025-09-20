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
    $RequestStatus = $Request.Query.RequestStatus
    $Filter = $Request.Query.Filter

    try {
        if ($TenantFilter -eq 'AllTenants') {
            throw 'AllTenants is not yet supported'
        }

        # Apply server-side filtering if requested
        $Uri = 'https://graph.microsoft.com/beta/identityGovernance/appConsent/appConsentRequests' # Need the beta endpoint to get consentType
        if ($Filter -eq $true -and $RequestStatus) {
            switch ($RequestStatus) {
                'InProgress' {
                    $FilterQuery = "userConsentRequests/any (u:u/status eq '$RequestStatus')"
                    $Uri = "$Uri`?`$filter=$([System.Web.HttpUtility]::UrlEncode($FilterQuery))"
                    Write-Host "Applying server-side filter for RequestStatus: $RequestStatus"
                    $ServerSideFilteringApplied = $true
                }
                default {
                    # All the other values are not supported yet even if the Graph API docs say they are. -Bobby
                    $ServerSideFilteringApplied = $false
                }
            }
        }

        $appConsentRequests = New-GraphGetRequest -Uri $Uri -tenantid $TenantFilter

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

        # Apply filtering if requested. Has to be done before and after the foreach loop, as the serverside filter is only supported for InProgress.
        if ($Filter -eq $true -and $ServerSideFilteringApplied -eq $false) {
            if ($RequestStatus) {
                Write-Host "Filtering by RequestStatus: $RequestStatus"
                $Results = $Results | Where-Object { $_.requestStatus -eq $RequestStatus }
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $StatusCode = [HttpStatusCode]::InternalServerError
        $Results = "Error: $($ErrorMessage.NormalizedError)"
    }

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })
}

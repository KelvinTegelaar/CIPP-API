function Invoke-ExecApproveAppConsentRequest {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.ReadWrite
    .DESCRIPTION
        Approves a pending app consent request by granting the delegated permissions it asks for to the application
        for all users in the tenant. The permissions are read from the request itself, not from the caller.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $AppId = $Request.Body.appId
    $GraphAppId = '00000003-0000-0000-c000-000000000000'

    try {
        $ConsentRequest = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/identityGovernance/appConsent/appConsentRequests' -tenantid $TenantFilter | Where-Object -Property appId -EQ $AppId | Select-Object -First 1
        $Scopes = @($ConsentRequest.pendingScopes.displayName)
        if ($ConsentRequest.consentType -eq 'Static' -or $Scopes -contains '.default') {
            throw "$($ConsentRequest.appDisplayName) asks for the permissions configured on its app registration, which cannot be read from this tenant. Approve it in Entra instead."
        }

        $ServicePrincipal = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$filter=appId eq '$AppId'&`$select=id" -tenantid $TenantFilter
        $GrantScopes = $Scopes
        if (!$ServicePrincipal) {
            $null = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/servicePrincipals' -tenantid $TenantFilter -type POST -body "{ `"appId`": `"$AppId`" }"
        } else {
            # Add-CIPPDelegatedPermission replaces the scopes of an existing grant, so pass the current ones along.
            $Graph = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/servicePrincipals(appId='$GraphAppId')?`$select=id" -tenantid $TenantFilter
            $CurrentGrant = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/servicePrincipals/$($ServicePrincipal.id)/oauth2PermissionGrants" -tenantid $TenantFilter | Where-Object { $_.consentType -eq 'AllPrincipals' -and $_.resourceId -eq $Graph.id }
            $GrantScopes = @($Scopes; $CurrentGrant.scope -split ' ' | Where-Object { $_ }) | Sort-Object -Unique
        }

        $RequiredResourceAccess = [pscustomobject]@{
            resourceAppId  = $GraphAppId
            resourceAccess = @($GrantScopes | ForEach-Object { [pscustomobject]@{ id = $_; type = 'Scope' } })
        }
        $Results = [System.Collections.Generic.List[object]]::new()
        foreach ($Result in Add-CIPPDelegatedPermission -RequiredResourceAccess $RequiredResourceAccess -ApplicationId $AppId -TenantFilter $TenantFilter) { $Results.Add($Result) }
        $Results.Add([pscustomobject]@{
                resultText = 'This item will remain in progress in the Microsoft portal, due to a lack of APIs. Deny the request in the portal to make this item no longer be in progress, or wait for it to expire'
                state      = 'warning'
            })
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Approved consent request for $($ConsentRequest.appDisplayName): $($Scopes -join ', ')" -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to approve the consent request: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = @($Results) }
        })
}

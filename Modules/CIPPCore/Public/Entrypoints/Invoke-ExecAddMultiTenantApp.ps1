using namespace System.Net

function Invoke-ExecAddMultiTenantApp {
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $DelegateResources = $request.body.permissions | Where-Object -Property origin -EQ 'Delegated' | ForEach-Object { @{ id = $_.id; type = 'Scope' } }
    $DelegateResourceAccess = @{ ResourceAppId = '00000003-0000-0000-c000-000000000000'; resourceAccess = $DelegateResources }
    $ApplicationResources = $request.body.permissions | Where-Object -Property origin -EQ 'Application' | ForEach-Object { @{ id = $_.id; type = 'Role' } }
    $ApplicationResourceAccess = @{ ResourceAppId = '00000003-0000-0000-c000-000000000000'; resourceAccess = $ApplicationResources }

    $Results = try {
        #This needs to be moved to a queue.
        if ('allTenants' -in $Request.body.SelectedTenants.defaultDomainName) { $TenantFilter = Get-Tenants } else { $TenantFilter = $Request.body.SelectedTenants.defaultDomainName }
        if ($request.body.CopyPermissions -eq $true) {
            try {
                $ExistingApp = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/applications(appId='$($Request.body.AppId)')" -tenantid $ENV:tenantid -NoAuthCheck $true
                $DelegateResourceAccess = $Existingapp.requiredResourceAccess
                $ApplicationResourceAccess = $Existingapp.requiredResourceAccess
            } catch {
                'Failed to get existing permissions. The app does not exist in the partner tenant.'
            }
        }

        foreach ($Tenant in $TenantFilter) {
            try {
                $ServicePrincipalList = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=AppId,id,displayName&`$top=999" -tenantid $Tenant
                if ($Request.body.AppId -Notin $ServicePrincipalList.appId) {
                    $PostResults = New-GraphPostRequest 'https://graph.microsoft.com/beta/servicePrincipals' -type POST -tenantid $tenant -body "{ `"appId`": `"$($Request.body.AppId)`" }"
                    "Added $($Request.body.AppId) to tenant $($Tenant)"
                } else {
                    "This app already exists in tenant $($Tenant). We're adding the required permissions."
                }

                Add-CIPPApplicationPermission -RequiredResourceAccess $applicationResourceAccess -ApplicationId $Request.body.AppId -Tenantfilter $Tenant
                Add-CIPPDelegatedPermission -RequiredResourceAccess $DelegateResourceAccess -ApplicationId $Request.body.AppId -Tenantfilter $Tenant
            } catch {
                "Error adding application to tenant $Tenant - $($_.Exception.Message)"
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMsg = Get-NormalizedError -message $($_.Exception.Message)
        $Results = "Function Error: $ErrorMsg"
        $StatusCode = [HttpStatusCode]::BadRequest
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = @($Results) }
        })

}
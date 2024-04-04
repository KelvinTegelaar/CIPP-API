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
        if ($request.body.CopyPermissions -eq $true) {
            try {
                $ExistingApp = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/applications(appId='$($Request.body.AppId)')" -tenantid $ENV:tenantid -NoAuthCheck $true
                $DelegateResourceAccess = $Existingapp.requiredResourceAccess
                $ApplicationResourceAccess = $Existingapp.requiredResourceAccess
            } catch {
                'Failed to get existing permissions. The app does not exist in the partner tenant.'
            }
        }
        #This needs to be moved to a queue.
        if ('allTenants' -in $Request.body.SelectedTenants.defaultDomainName) {
            $TenantFilter = (Get-Tenants).defaultDomainName 
        } else {
            $TenantFilter = $Request.body.SelectedTenants.defaultDomainName 
        }

        foreach ($Tenant in $TenantFilter) {
            try {
                Push-OutputBinding -Name QueueItem -Value ([pscustomobject]@{
                        FunctionName              = 'ExecAddMultiTenantApp'
                        Tenant                    = $tenant
                        appId                     = $Request.body.appid
                        applicationResourceAccess = $ApplicationResourceAccess
                        delegateResourceAccess    = $DelegateResourceAccess
                    })
                "Queued application to tenant $Tenant. See the logbook for deployment details"
            } catch {
                "Error queuing application to tenant $Tenant - $($_.Exception.Message)"
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
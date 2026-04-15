function Push-ExecAddMultiTenantApp {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)
    try {
        $Item = $Item | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        Write-Host "$($Item | ConvertTo-Json -Depth 10)"
        $ServicePrincipalList = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=AppId,id,displayName&`$top=999" -tenantid $Item.Tenant
        if ($Item.AppId -Notin $ServicePrincipalList.appId) {
            $PostResults = New-GraphPostRequest 'https://graph.microsoft.com/beta/servicePrincipals' -type POST -tenantid $Item.tenant -body "{ `"appId`": `"$($Item.appId)`" }"
            Write-LogMessage -message "Added $($Item.AppId) to tenant $($Item.Tenant)" -tenant $Item.Tenant -API 'Add Multitenant App' -sev Info
        } else {
            Write-LogMessage -message "This app already exists in tenant $($Item.Tenant). We're adding the required permissions." -tenant $Item.Tenant -API 'Add Multitenant App' -sev Info
        }
        Add-CIPPApplicationPermission -RequiredResourceAccess ($Item.applicationResourceAccess) -ApplicationId $Item.AppId -Tenantfilter $Item.Tenant
        Add-CIPPDelegatedPermission -RequiredResourceAccess ($Item.DelegateResourceAccess) -ApplicationId $Item.AppId -Tenantfilter $Item.Tenant
    } catch {
        Write-LogMessage -message "Error adding application to tenant $($Item.Tenant) - $($_.Exception.Message)" -tenant $Item.Tenant -API 'Add Multitenant App' -sev Error
    }
}

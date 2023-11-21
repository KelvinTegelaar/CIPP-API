function Push-ExecAddMultiTenantApp($QueueItem, $TriggerMetadata) {
    try {
        Write-Host $Queueitem
        $ServicePrincipalList = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=AppId,id,displayName&`$top=999" -tenantid $Queueitem.Tenant
        if ($Queueitem.AppId -Notin $ServicePrincipalList.appId) {
            $PostResults = New-GraphPostRequest 'https://graph.microsoft.com/beta/servicePrincipals' -type POST -tenantid $queueitem.tenant -body "{ `"appId`": `"$($Queueitem.appId)`" }"
            Write-LogMessage -message "Added $($Queueitem.AppId) to tenant $($Queueitem.Tenant)" -tenant $Queueitem.Tenant -API "Add Multitenant App" -sev Info
        }
        else {
            Write-LogMessage -message "This app already exists in tenant $($Queueitem.Tenant). We're adding the required permissions." -tenant $Queueitem.Tenant -API "Add Multitenant App" -sev Info
        }

        Add-CIPPApplicationPermission -RequiredResourceAccess $queueitem.applicationResourceAccess -ApplicationId $queueitem.AppId -Tenantfilter $Queueitem.Tenant
        Add-CIPPDelegatedPermission -RequiredResourceAccess $queueitem.DelegateResourceAccess -ApplicationId $queueitem.AppId -Tenantfilter $Queueitem.Tenant
    }
    catch {
        Write-LogMessage -message "Error adding application to tenant $($Queueitem.Tenant) - $($_.Exception.Message)"  -tenant $Queueitem.Tenant -API "Add Multitenant App" -sev Error
    }
}
function Push-ExecAppApprovalTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    try {
        $Item = $Item | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $TemplateId = $Item.templateId
        if (!$TemplateId) {
            Write-LogMessage -message 'No template specified' -tenant $Item.Tenant -API 'Add Multitenant App' -sev Error
            return
        }

        $ServicePrincipalList = New-GraphGETRequest -uri "https://graph.microsoft.com/beta/servicePrincipals?`$select=AppId,id,displayName&`$top=999" -tenantid $Item.Tenant
        if ($Item.AppId -notin $ServicePrincipalList.appId) {
            Write-Information "Adding $($Item.AppId) to tenant $($Item.Tenant)."
            $PostResults = New-GraphPostRequest 'https://graph.microsoft.com/beta/servicePrincipals' -type POST -tenantid $Item.tenant -body "{ `"appId`": `"$($Item.appId)`" }"
            Write-LogMessage -message "Added $($Item.AppId) to tenant $($Item.Tenant)" -tenant $Item.Tenant -API 'Add Multitenant App' -sev Info
        } else {
            Write-LogMessage -message "This app already exists in tenant $($Item.Tenant). We're adding the required permissions." -tenant $Item.Tenant -API 'Add Multitenant App' -sev Info
        }
        Add-CIPPApplicationPermission -TemplateId $TemplateId -Tenantfilter $Item.Tenant
        Add-CIPPDelegatedPermission -TemplateId $TemplateId -Tenantfilter $Item.Tenant
    } catch {
        Write-LogMessage -message "Error adding application to tenant $($Item.Tenant) - $($_.Exception.Message)" -tenant $Item.Tenant -API 'Add Multitenant App' -sev Error
        Write-Error $_.Exception.Message
    }
}

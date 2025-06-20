function Invoke-CIPPStandardAppDeploy {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) AppDeploy
    .SYNOPSIS
        (Label) Deploy Application
    .DESCRIPTION
        (Helptext) Deploys selected applications to the tenant. Use a comma separated list of application IDs to deploy multiple applications. Permissions will be copied from the source application.
        (DocsDescription) Uses the CIPP functionality that deploys applications across an entire tenant base as a standard.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        ADDEDCOMPONENT
            {"type":"select","multiple":false,"creatable":false,"label":"App Approval Mode","name":"standards.AppDeploy.mode","options":[{"label":"Template","value":"template"},{"label":"Copy Permissions","value":"copy"}]}
            {"type":"autoComplete","multiple":true,"creatable":false,"label":"Select Applications","name":"standards.AppDeploy.templateIds","api":{"url":"/api/ListAppApprovalTemplates","labelField":"TemplateName","valueField":"TemplateId","queryKey":"StdAppApprovalTemplateList","addedField":{"AppId":"AppId"}},"condition":{"field":"standards.AppDeploy.mode","compareType":"is","compareValue":"template"}}
            {"type":"textField","name":"standards.AppDeploy.appids","label":"Application IDs, comma separated","condition":{"field":"standards.AppDeploy.mode","compareType":"isNot","compareValue":"template"}}
        IMPACT
            Low Impact
        ADDEDDATE
            2024-07-07
        POWERSHELLEQUIVALENT
            Portal or Graph API
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>

    param($Tenant, $Settings)
    Write-Information "Running AppDeploy standard for tenant $($Tenant)."

    $AppsToAdd = $Settings.appids -split ','
    $AppExists = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/servicePrincipals?$top=999' -tenantid $Tenant
    $Mode = $Settings.mode ?? 'copy'

    if ($Mode -eq 'template') {
        $AppsToAdd = $Settings.templateIds.addedFields.AppId
    }

    $MissingApps = foreach ($App in $AppsToAdd) {
        if ($App -notin $AppExists.appId) {
            $App
        }
    }
    if ($Settings.remediate -eq $true) {
        if ($Mode -eq 'copy') {
            foreach ($App in $AppsToAdd) {
                $App = $App.Trim()
                if (!$App) {
                    continue
                }
                $Application = $AppExists | Where-Object -Property appId -EQ $App
                try {
                    New-CIPPApplicationCopy -App $App -Tenant $Tenant
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Added application $($Application.displayName) ($App) to $Tenant and updated it's permissions" -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to add app $($Application.displayName) ($App). Error: $ErrorMessage" -sev Error
                }
            }
        } elseif ($Mode -eq 'template') {
            $TemplateIds = $Settings.templateIds.value
            $TemplateName = $Settings.templateIds.label
            $AppIds = $Settings.templateIds.addedFields.AppId

            foreach ($AppId in $AppIds) {
                if ($AppId -notin $AppExists.appId) {
                    Write-Information "Adding $AppId to tenant $Tenant."
                    $PostResults = New-GraphPostRequest 'https://graph.microsoft.com/beta/servicePrincipals' -type POST -tenantid $Tenant -body "{ `"appId`": `"$AppId`" }"
                    Write-LogMessage -message "Added $AppId to tenant $Tenant" -tenant $Tenant -API 'Add Multitenant App' -sev Info
                }
            }
            foreach ($TemplateId in $TemplateIds) {
                try {
                    Add-CIPPApplicationPermission -TemplateId $TemplateId -TenantFilter $Tenant
                    Add-CIPPDelegatedPermission -TemplateId $TemplateId -TenantFilter $Tenant
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Added application(s) from template $($TemplateName) and updated it's permissions" -sev Info
                } catch {
                    $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                    Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to add app from approval template $($TemplateName). Error: $ErrorMessage" -sev Error
                }
            }
        }
    }

    if ($Settings.alert) {
        if ($MissingApps.Count -gt 0) {
            Write-StandardsAlert -message "The following applications are not deployed: $($MissingApps -join ', ')" -object (@{ 'Missing Apps' = $MissingApps -join ',' }) -tenant $Tenant -standardName 'AppDeploy' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $tenant -message "The following applications are not deployed: $($MissingApps -join ', ')" -sev Info
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message 'All applications are deployed' -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $StateIsCorrect = $MissingApps.Count -eq 0 ? $true : @{ 'Missing Apps' = $MissingApps -join ',' }
        Set-CIPPStandardsCompareField -FieldName 'standards.AppDeploy' -FieldValue $StateIsCorrect -TenantFilter $tenant
        Add-CIPPBPAField -FieldName 'AppDeploy' -FieldValue $StateIsCorrect -StoreAs bool -Tenant $tenant
    }

}

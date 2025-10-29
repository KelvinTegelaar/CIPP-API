function Invoke-CIPPStandardConditionalAccessTemplate {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) ConditionalAccessTemplate
    .SYNOPSIS
        (Label) Conditional Access Template
    .DESCRIPTION
        (Helptext) Manage conditional access policies for better security.
        (DocsDescription) Manage conditional access policies for better security.
    .NOTES
        CAT
            Templates
        MULTIPLE
            True
        DISABLEDFEATURES
            {"report":true,"warn":true,"remediate":false}
        IMPACT
            High Impact
        ADDEDDATE
            2023-12-30
        EXECUTIVETEXT
            Deploys standardized conditional access policies that automatically enforce security requirements based on user location, device compliance, and risk factors. These templates ensure consistent security controls across the organization while enabling secure access to business resources.
        ADDEDCOMPONENT
            {"type":"autoComplete","name":"TemplateList","multiple":false,"label":"Select Conditional Access Template","api":{"url":"/api/ListCATemplates","labelField":"displayName","valueField":"GUID","queryKey":"ListCATemplates"}}
            {"name":"state","label":"What state should we deploy this template in?","type":"radio","options":[{"value":"donotchange","label":"Do not change state"},{"value":"Enabled","label":"Set to enabled"},{"value":"Disabled","label":"Set to disabled"},{"value":"enabledForReportingButNotEnforced","label":"Set to report only"}]}
            {"type":"switch","name":"DisableSD","label":"Disable Security Defaults when deploying policy"}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'ConditionalAccess'
    $Table = Get-CippTable -tablename 'templates'
    $TestResult = Test-CIPPStandardLicense -StandardName 'ConditionalAccessTemplate_general' -TenantFilter $Tenant -RequiredCapabilities @('AAD_PREMIUM', 'AAD_PREMIUM_P2')
    $TestP2 = Test-CIPPStandardLicense -StandardName 'ConditionalAccessTemplate_p2' -TenantFilter $Tenant -RequiredCapabilities @('AAD_PREMIUM_P2') -SkipLog
    if ($TestResult -eq $false) {
        #writing to each item that the license is not present.
        $settings.TemplateList | ForEach-Object {
            Set-CIPPStandardsCompareField -FieldName "standards.ConditionalAccessTemplate.$($_.value)" -FieldValue 'This tenant does not have the required license for this standard.' -Tenant $Tenant
        }
        Write-Host "We're exiting as the correct license is not present for this standard."
        return $true
    } #we're done.

    try {
        $AllCAPolicies = New-GraphGetRequest -Uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/policies?$top=999' -tenantid $Tenant -asApp $true
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the ConditionalAccessTemplate state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        foreach ($Setting in $Settings) {
            try {
                $Filter = "PartitionKey eq 'CATemplate' and RowKey eq '$($Setting.TemplateList.value)'"
                $JSONObj = (Get-CippAzDataTableEntity @Table -Filter $Filter).JSON
                $Policy = $JSONObj | ConvertFrom-Json
                if ($Policy.conditions.userRiskLevels.count -gt 0 -or $Policy.conditions.signInRiskLevels.count -gt 0) {
                    if (!$TestP2) {
                        Write-Information "Skipping policy $($Policy.displayName) as it requires AAD Premium P2 license."
                        Set-CIPPStandardsCompareField -FieldName "standards.ConditionalAccessTemplate.$($Setting.value)" -FieldValue "Policy $($Policy.displayName) requires AAD Premium P2 license." -Tenant $Tenant
                        continue
                    }
                }
                $null = New-CIPPCAPolicy -replacePattern 'displayName' -TenantFilter $tenant -state $Setting.state -RawJSON $JSONObj -Overwrite $true -APIName $APIName -Headers $Request.Headers -DisableSD $Setting.DisableSD
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to create or update conditional access rule $($JSONObj.displayName). Error: $ErrorMessage" -sev 'Error'
            }
        }
    }
    if ($Settings.report -eq $true -or $Settings.remediate -eq $true) {
        $Filter = "PartitionKey eq 'CATemplate'"
        $Policies = (Get-CippAzDataTableEntity @Table -Filter $Filter | Where-Object RowKey -In $Settings.TemplateList.value).JSON | ConvertFrom-Json -Depth 10
        #check if all groups.displayName are in the existingGroups, if not $fieldvalue should contain all missing groups, else it should be true.
        $MissingPolicies = foreach ($Setting in $Settings.TemplateList) {
            $policy = $Policies | Where-Object { $_.displayName -eq $Setting.label }
            $CheckExististing = $AllCAPolicies | Where-Object -Property displayName -EQ $Setting.label
            if (!$CheckExististing) {
                if ($Setting.conditions.userRiskLevels.Count -gt 0 -or $Setting.conditions.signInRiskLevels.Count -gt 0) {
                    if (!$TestP2) {
                        Set-CIPPStandardsCompareField -FieldName "standards.ConditionalAccessTemplate.$($Setting.value)" -FieldValue "Policy $($Setting.label) requires AAD Premium P2 license." -Tenant $Tenant
                    } else {
                        Set-CIPPStandardsCompareField -FieldName "standards.ConditionalAccessTemplate.$($Setting.value)" -FieldValue "Policy $($Setting.label) is missing from this tenant." -Tenant $Tenant
                    }
                } else {
                    Set-CIPPStandardsCompareField -FieldName "standards.ConditionalAccessTemplate.$($Setting.value)" -FieldValue "Policy $($Setting.label) is missing from this tenant." -Tenant $Tenant
                }
            } else {
                $CompareObj = ConvertFrom-Json -ErrorAction SilentlyContinue -InputObject (New-CIPPCATemplate -TenantFilter $tenant -JSON $CheckExististing)
                $Compare = Compare-CIPPIntuneObject -ReferenceObject $policy -DifferenceObject $CompareObj
                if (!$Compare) {
                    Set-CIPPStandardsCompareField -FieldName "standards.ConditionalAccessTemplate.$($Setting.value)" -FieldValue $true -Tenant $Tenant
                } else {
                    Set-CIPPStandardsCompareField -FieldName "standards.ConditionalAccessTemplate.$($Setting.value)" -FieldValue $Compare -Tenant $Tenant
                }
            }
        }
    }
}

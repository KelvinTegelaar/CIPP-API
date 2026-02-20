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
            {"type":"autoComplete","name":"TemplateList","multiple":false,"label":"Select Conditional Access Template","api":{"url":"/api/ListCATemplates","labelField":"displayName","valueField":"GUID","queryKey":"ListCATemplates","showRefresh":true,"templateView":{"title":"Conditional Access Policy"}}}
            {"name":"state","label":"What state should we deploy this template in?","type":"radio","options":[{"value":"donotchange","label":"Do not change state"},{"value":"Enabled","label":"Set to enabled"},{"value":"Disabled","label":"Set to disabled"},{"value":"enabledForReportingButNotEnforced","label":"Set to report only"}]}
            {"type":"switch","name":"DisableSD","label":"Disable Security Defaults when deploying policy"}
            {"type":"switch","name":"CreateGroups","label":"Create groups if they do not exist"}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    param($Tenant, $Settings)

    #Checking if the DB has been updated in the last 3h, if not, run an update before we run the standard, as CA policies are critical and we want to make sure we have the latest state before making changes or comparisons.
    $LastDBUpdate = Get-CIPPDbItem -TenantFilter $Tenant -Type 'ConditionalAccessPolicies' -CountsOnly
    if ($LastDBUpdate -eq $null -or ($LastDBUpdate.Timestamp -lt (Get-Date).AddHours(-3) -or $LastDBUpdate.DataCount -eq 0)) {
        Write-Information "DB last updated at $($LastDBUpdate.Timestamp). Updating DB before running standard, this is probably a manual run."
        Set-CIPPDBCacheConditionalAccessPolicies -TenantFilter $Tenant
    } else {
        Write-Information "DB last updated at $($LastDBUpdate.Timestamp). No need to update before running standard."
    }


    $TestResult = Test-CIPPStandardLicense -StandardName 'ConditionalAccessTemplate_general' -TenantFilter $Tenant -RequiredCapabilities @('AAD_PREMIUM', 'AAD_PREMIUM_P2')
    if ($TestResult -eq $false) {
        Set-CIPPStandardsCompareField -FieldName "standards.ConditionalAccessTemplate.$($Settings.TemplateList.value)" -FieldValue 'This tenant does not have the required license for this standard.' -Tenant $Tenant
        return $true
    } #we're done.

    $Table = Get-CippTable -tablename 'templates'

    try {
        #Get from DB, as we just downloaded the latest before the standard runs.
        $AllCAPolicies = New-CIPPDbRequest -TenantFilter $tenant -Type 'ConditionalAccessPolicies'
        $PreloadedLocations = New-CIPPDbRequest -TenantFilter $tenant -Type 'NamedLocations'
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the ConditionalAccessTemplate state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    if ($Settings.remediate -eq $true) {
        try {
            $Filter = "PartitionKey eq 'CATemplate' and RowKey eq '$($Settings.TemplateList.value)'"
            $JSONObj = (Get-CippAzDataTableEntity @Table -Filter $Filter).JSON
            $Policy = $JSONObj | ConvertFrom-Json
            if ($Policy.conditions.userRiskLevels.count -gt 0 -or $Policy.conditions.signInRiskLevels.count -gt 0) {
                $TestP2 = Test-CIPPStandardLicense -StandardName 'ConditionalAccessTemplate_p2' -TenantFilter $Tenant -RequiredCapabilities @('AAD_PREMIUM_P2') -SkipLog
                if (!$TestP2) {
                    Write-Information "Skipping policy $($Policy.displayName) as it requires AAD Premium P2 license."
                    Set-CIPPStandardsCompareField -FieldName "standards.ConditionalAccessTemplate.$($Settings.TemplateList.value)" -FieldValue "Policy $($Policy.displayName) requires AAD Premium P2 license." -Tenant $Tenant
                    return $true
                }
            }
            $NewCAPolicy = @{
                replacePattern      = 'displayName'
                TenantFilter        = $Tenant
                state               = $Settings.state
                RawJSON             = $JSONObj
                Overwrite           = $true
                APIName             = 'Standards'
                Headers             = $Request.Headers
                DisableSD           = $Settings.DisableSD
                CreateGroups        = $Settings.CreateGroups ?? $false
                PreloadedCAPolicies = $AllCAPolicies
                PreloadedLocations  = $PreloadedLocations
            }

            $null = New-CIPPCAPolicy @NewCAPolicy
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to create or update conditional access rule $($JSONObj.displayName). Error: $ErrorMessage" -sev 'Error'
        }
    }
    if ($Settings.report -eq $true -or $Settings.remediate -eq $true) {
        $Filter = "PartitionKey eq 'CATemplate' and RowKey eq '$($Settings.TemplateList.value)'"
        $Policy = (Get-CippAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json -Depth 10

        $CheckExististing = $AllCAPolicies | Where-Object -Property displayName -EQ $Settings.TemplateList.label
        if (!$CheckExististing) {
            if ($Policy.conditions.userRiskLevels.Count -gt 0 -or $Policy.conditions.signInRiskLevels.Count -gt 0) {
                $TestP2 = Test-CIPPStandardLicense -StandardName 'ConditionalAccessTemplate_p2' -TenantFilter $Tenant -RequiredCapabilities @('AAD_PREMIUM_P2') -SkipLog
                if (!$TestP2) {
                    Set-CIPPStandardsCompareField -FieldName "standards.ConditionalAccessTemplate.$($Settings.TemplateList.value)" -FieldValue "Policy $($Settings.TemplateList.label) requires AAD Premium P2 license." -Tenant $Tenant
                } else {
                    Set-CIPPStandardsCompareField -FieldName "standards.ConditionalAccessTemplate.$($Settings.TemplateList.value)" -FieldValue "Policy $($Settings.TemplateList.label) is missing from this tenant." -Tenant $Tenant
                }
            } else {
                Set-CIPPStandardsCompareField -FieldName "standards.ConditionalAccessTemplate.$($Settings.TemplateList.value)" -FieldValue "Policy $($Settings.TemplateList.label) is missing from this tenant." -Tenant $Tenant
            }
        } else {
            $templateResult = New-CIPPCATemplate -TenantFilter $tenant -JSON $CheckExististing -preloadedLocations $preloadedLocations
            $CompareObj = ConvertFrom-Json -ErrorAction SilentlyContinue -InputObject $templateResult
            try {
                $Compare = Compare-CIPPIntuneObject -ReferenceObject $Policy -DifferenceObject $CompareObj -CompareType 'ca'
            } catch {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Error comparing CA policy: $($_.Exception.Message)" -sev Error
                Set-CIPPStandardsCompareField -FieldName "standards.ConditionalAccessTemplate.$($Settings.TemplateList.value)" -FieldValue "Error comparing policy: $($_.Exception.Message)" -Tenant $Tenant
                return
            }
            if (!$Compare) {
                Set-CIPPStandardsCompareField -FieldName "standards.ConditionalAccessTemplate.$($Settings.TemplateList.value)" -FieldValue $true -Tenant $Tenant
            } else {
                #this can still be prettified but is for later.
                $ExpectedValue = @{ 'Differences' = @() }
                $CurrentValue = @{ 'Differences' = $Compare }
                Set-CIPPStandardsCompareField -FieldName "standards.ConditionalAccessTemplate.$($Settings.TemplateList.value)" -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
            }
        }
    }
}

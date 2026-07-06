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
            {"type":"autoComplete","name":"TemplateList","multiple":false,"required":false,"creatable":false,"label":"Select Conditional Access Template","api":{"url":"/api/ListCATemplates","labelField":"displayName","valueField":"GUID","queryKey":"ListCATemplates","showRefresh":true,"templateView":{"title":"Conditional Access Policy"}}}
            {"type":"autoComplete","multiple":false,"required":false,"creatable":false,"name":"TemplateList-Tags","label":"Or select a package of CA Templates","api":{"queryKey":"ListCATemplates-tag-autocomplete","url":"/api/ListCATemplates?mode=Tag","labelField":"label","valueField":"value","addedField":{"templates":"templates"}}}
            {"name":"state","label":"What state should we deploy this template in?","type":"radio","options":[{"value":"donotchange","label":"Do not change state"},{"value":"Enabled","label":"Set to enabled"},{"value":"Disabled","label":"Set to disabled"},{"value":"enabledForReportingButNotEnforced","label":"Set to report only"}]}
            {"type":"switch","name":"DisableSD","label":"Disable Security Defaults when deploying policy"}
            {"type":"switch","name":"CreateGroups","label":"Create groups if they do not exist"}
        REQUIREDCAPABILITIES
            "AAD_PREMIUM"
            "AAD_PREMIUM_P2"
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
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


    $TestResult = Test-CIPPStandardLicense -StandardName 'ConditionalAccessTemplate_general' -TenantFilter $Tenant -Preset Entra
    if ($TestResult -eq $false) {
        Set-CIPPStandardsCompareField -FieldName "standards.ConditionalAccessTemplate.$($Settings.TemplateList.value)" -FieldValue 'This tenant does not have the required license for this standard.' -Tenant $Tenant
        return $true
    } #we're done.

    $Table = Get-CippTable -tablename 'templates'

    try {
        #Get from DB, as we just downloaded the latest before the standard runs.
        $AllCAPolicies = New-CIPPDbRequest -TenantFilter $tenant -Type 'ConditionalAccessPolicies'
        $PreloadedLocations = New-CIPPDbRequest -TenantFilter $tenant -Type 'NamedLocations'
        $PreloadedSecurityDefaults = New-CIPPDbRequest -TenantFilter $tenant -Type 'SecurityDefaults'
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        Write-LogMessage -API 'Standards' -Tenant $Tenant -Message "Could not get the ConditionalAccessTemplate state for $Tenant. Error: $ErrorMessage" -Sev Error
        return
    }

    $DeployError = $null
    if ($Settings.remediate -eq $true) {
        try {
            $Filter = "PartitionKey eq 'CATemplate' and RowKey eq '$($Settings.TemplateList.value)'"
            $JSONObj = (Get-CippAzDataTableEntity @Table -Filter $Filter).JSON
            $Policy = $JSONObj | ConvertFrom-Json
            if ($Policy.conditions.userRiskLevels.count -gt 0 -or $Policy.conditions.signInRiskLevels.count -gt 0) {
                $TestP2 = Test-CIPPStandardLicense -StandardName 'ConditionalAccessTemplate_p2' -TenantFilter $Tenant -Preset EntraP2 -SkipLog
                if (!$TestP2) {
                    Write-Information "Skipping policy $($Policy.displayName) as it requires AAD Premium P2 license."
                    Set-CIPPStandardsCompareField -FieldName "standards.ConditionalAccessTemplate.$($Settings.TemplateList.value)" -CurrentValue @{ Differences = 'Policy requires an AAD Premium P2 license, which this tenant does not have.' } -ExpectedValue @{ Differences = @() } -Tenant $Tenant
                    return $true
                }
            }
            $NewCAPolicy = @{
                replacePattern            = 'displayName'
                TenantFilter              = $Tenant
                state                     = $Settings.state
                RawJSON                   = $JSONObj
                Overwrite                 = $true
                APIName                   = 'Standards'
                Headers                   = $Request.Headers
                DisableSD                 = $Settings.DisableSD
                CreateGroups              = $Settings.CreateGroups ?? $false
                PreloadedCAPolicies       = $AllCAPolicies
                PreloadedLocations        = $PreloadedLocations
                PreloadedSecurityDefaults = $PreloadedSecurityDefaults
            }

            $null = New-CIPPCAPolicy @NewCAPolicy
        } catch {
            # Capture the Graph deploy error (e.g. invalid CA policy 1011/1085) so the report
            # section below surfaces the reason in the compare fields instead of just "missing".
            $DeployError = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to create or update conditional access rule $($JSONObj.displayName). Error: $DeployError" -sev 'Error'
        }
    }
    if ($Settings.report -eq $true -or $Settings.remediate -eq $true) {
        $FieldName = "standards.ConditionalAccessTemplate.$($Settings.TemplateList.value)"
        $Filter = "PartitionKey eq 'CATemplate' and RowKey eq '$($Settings.TemplateList.value)'"
        $Policy = (Get-CippAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json -Depth 10

        if ($null -eq $Policy) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Conditional Access template '$($Settings.TemplateList.label)' ($($Settings.TemplateList.value)) could not be loaded from the template store - skipping." -Sev 'Error'
            Set-CIPPStandardsCompareField -FieldName $FieldName -CurrentValue @{ Differences = "Template '$($Settings.TemplateList.label)' could not be loaded from the template store." } -ExpectedValue @{ Differences = @() } -Tenant $Tenant
            return
        }

        # Override the template's state with the Drift Standard's state if specified
        # This ensures drift detection compares against the desired state, not the original template state
        if ($Settings.state -and $Settings.state -ne 'donotchange') {
            Write-Information "Overriding template state from '$($Policy.state)' to '$($Settings.state)' for drift comparison"
            $Policy | Add-Member -NotePropertyName 'state' -NotePropertyValue $Settings.state -Force
        }

        # Resolve the template's location GUIDs to display names so they compare like-for-like
        # with the deployed policy. The template's own LocationInfo carries the id->name map
        # (the GUID is the source tenant's id); fall back to this tenant's named-location cache.
        if ($Policy.conditions.locations) {
            $LocNameById = @{}
            foreach ($li in @($Policy.LocationInfo)) { if ($li.id -and $li.displayName) { $LocNameById[$li.id] = $li.displayName } }
            foreach ($pl in @($PreloadedLocations)) { if ($pl.id -and $pl.displayName -and -not $LocNameById.ContainsKey($pl.id)) { $LocNameById[$pl.id] = $pl.displayName } }
            foreach ($LocDir in 'includeLocations', 'excludeLocations') {
                if ($Policy.conditions.locations.PSObject.Properties.Name -contains $LocDir -and $Policy.conditions.locations.$LocDir) {
                    $Policy.conditions.locations.$LocDir = @($Policy.conditions.locations.$LocDir | ForEach-Object {
                            if ($LocNameById.ContainsKey($_)) { $LocNameById[$_] } else { $_ }
                        })
                }
            }
        }

        $CheckExististing = $AllCAPolicies | Where-Object -Property displayName -EQ $Settings.TemplateList.label
        # Duplicate display names would pass an array to New-CIPPCATemplate (breaking its single-object
        # conversion and dumping the whole template). Compare against the first match instead.
        if ($CheckExististing -is [array] -and $CheckExististing.Count -gt 1) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Found $($CheckExististing.Count) Conditional Access policies named '$($Settings.TemplateList.label)' in $Tenant. Comparing against the first; duplicate policies should be cleaned up." -Sev 'Warning'
            $CheckExististing = $CheckExististing[0]
        }
        if (!$CheckExististing) {
            if ($DeployError) {
                # Attempted but the Graph deployment errored (e.g. invalid CA policy) - surface the reason
                Set-CIPPStandardsCompareField -FieldName $FieldName -CurrentValue @{ Differences = "Failed to deploy: $DeployError" } -ExpectedValue @{ Differences = @() } -Tenant $Tenant
            } elseif ($Policy.conditions.userRiskLevels.Count -gt 0 -or $Policy.conditions.signInRiskLevels.Count -gt 0) {
                $TestP2 = Test-CIPPStandardLicense -StandardName 'ConditionalAccessTemplate_p2' -TenantFilter $Tenant -Preset EntraP2 -SkipLog
                if (!$TestP2) {
                    Set-CIPPStandardsCompareField -FieldName $FieldName -CurrentValue @{ Differences = 'Policy requires an AAD Premium P2 license, which this tenant does not have.' } -ExpectedValue @{ Differences = @() } -Tenant $Tenant
                } else {
                    Set-CIPPStandardsCompareField -FieldName $FieldName -CurrentValue @{ Differences = 'Policy is missing from this tenant.' } -ExpectedValue @{ Differences = @() } -Tenant $Tenant
                }
            } else {
                Set-CIPPStandardsCompareField -FieldName $FieldName -CurrentValue @{ Differences = 'Policy is missing from this tenant.' } -ExpectedValue @{ Differences = @() } -Tenant $Tenant
            }
        } else {
            $templateResult = New-CIPPCATemplate -TenantFilter $tenant -JSON $CheckExististing -preloadedLocations $PreloadedLocations
            $CompareObj = ConvertFrom-Json -ErrorAction SilentlyContinue -InputObject $templateResult
            if ($null -eq $CompareObj) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Cannot compare CA policy: tenant policy conversion returned null for $($Settings.TemplateList.label)" -sev Error
                Set-CIPPStandardsCompareField -FieldName $FieldName -CurrentValue @{ Differences = 'Tenant policy conversion returned null.' } -ExpectedValue @{ Differences = @() } -Tenant $Tenant
                return
            }
            try {
                $Compare = Compare-CIPPIntuneObject -ReferenceObject $Policy -DifferenceObject $CompareObj -CompareType 'ca'
            } catch {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Error comparing CA policy: $($_.Exception.Message)" -sev Error
                Set-CIPPStandardsCompareField -FieldName $FieldName -CurrentValue @{ Differences = "Error comparing policy: $($_.Exception.Message)" } -ExpectedValue @{ Differences = @() } -Tenant $Tenant
                return
            }
            if (!$Compare) {
                $ExpectedValue = @{ 'Differences' = 'No Differences found' }
                $CurrentValue = @{ 'Differences' = 'No Differences found' }
                Set-CIPPStandardsCompareField -FieldName $FieldName -FieldValue $true -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
            } else {
                $ExpectedValue = @{ 'Differences' = @() }
                $CurrentValue = @{ 'Differences' = $Compare }
                Set-CIPPStandardsCompareField -FieldName $FieldName -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -Tenant $Tenant
            }
        }
    }
}

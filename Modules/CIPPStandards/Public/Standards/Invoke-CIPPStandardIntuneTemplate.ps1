function Invoke-CIPPStandardIntuneTemplate {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) IntuneTemplate
    .SYNOPSIS
        (Label) Intune Template
    .DESCRIPTION
        (Helptext) Deploy and manage Intune templates across devices.
        (DocsDescription) Deploy and manage Intune templates across devices.
    .NOTES
        CAT
            Templates
        MULTIPLE
            True
        DISABLEDFEATURES
            {"report":false,"warn":false,"remediate":false}
        IMPACT
            High Impact
        ADDEDDATE
            2023-12-30
        EXECUTIVETEXT
            Deploys standardized device management configurations across all corporate devices, ensuring consistent security policies, application settings, and compliance requirements. This template-based approach streamlines device management while maintaining uniform security standards across the organization.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"required":false,"name":"TemplateList","label":"Select Intune Template","api":{"queryKey":"ListIntuneTemplates-autcomplete","url":"/api/ListIntuneTemplates","labelField":"Displayname","valueField":"GUID","showRefresh":true,"templateView":{"title":"Intune Template","property":"RAWJson","type":"intune"}}}
            {"type":"autoComplete","multiple":false,"required":false,"creatable":false,"name":"TemplateList-Tags","label":"Or select a package of Intune Templates","api":{"queryKey":"ListIntuneTemplates-tag-autcomplete","url":"/api/ListIntuneTemplates?mode=Tag","labelField":"label","valueField":"value"}}
            {"name":"AssignTo","label":"Who should this template be assigned to?","type":"radio","options":[{"label":"Do not assign","value":"On"},{"label":"Assign to all users","value":"allLicensedUsers"},{"label":"Assign to all devices","value":"AllDevices"},{"label":"Assign to all users and devices","value":"AllDevicesAndUsers"},{"label":"Assign to Custom Group","value":"customGroup"}]}
            {"type":"textField","required":false,"name":"customGroup","label":"Enter the custom group name if you selected 'Assign to Custom Group'. Wildcards are allowed."}
            {"type":"switch","name":"verifyAssignments","label":"Verify policy assignments"}
            {"name":"excludeGroup","label":"Exclude Groups","type":"textField","required":false,"helpText":"Enter the group name(s) to exclude from the assignment. Wildcards are allowed. Multiple group names are comma-seperated."}
            {"type":"textField","required":false,"name":"assignmentFilter","label":"Assignment Filter Name (Optional)","helpText":"Enter the assignment filter name to apply to this policy assignment. Wildcards are allowed."}
            {"name":"assignmentFilterType","label":"Assignment Filter Mode (Optional)","type":"radio","required":false,"helpText":"Choose whether to include or exclude devices matching the filter. Only applies if you specified a filter name above. Defaults to Include if not specified.","options":[{"label":"Include - Assign to devices matching the filter","value":"include"},{"label":"Exclude - Assign to devices NOT matching the filter","value":"exclude"}]}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    param($Tenant, $Settings)

    Write-Host 'INTUNETEMPLATERUN'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $lap = $sw.Elapsed

    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'IntuneTemplate'"

    $Template = (Get-CIPPAzDataTableEntity @Table -Filter $Filter | Where-Object -Property RowKey -Like "$($Settings.TemplateList.value)*").JSON | ConvertFrom-Json -ErrorAction SilentlyContinue
    Write-Information "[IntuneTemplate][$Tenant] TableLoad: $([int]($sw.Elapsed - $lap).TotalMilliseconds)ms"
    $lap = $sw.Elapsed

    if ($null -eq $Template) {
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to find template $($Settings.TemplateList.value). Has this Intune Template been deleted?" -sev 'Error'
        return $true
    }

    $Template = Repair-CIPPIntuneTemplateNesting -Template $Template -Table $Table

    $rawJsonFromTemplate = $Template.RAWJson
    try {
        $reusableSync = Sync-CIPPReusablePolicySettings -TemplateInfo $Template -Tenant $Tenant -ErrorAction Stop
        if ($null -ne $reusableSync -and $reusableSync.PSObject.Properties.Name -contains 'RawJSON' -and $reusableSync.RawJSON) {
            $rawJsonFromTemplate = $reusableSync.RawJSON
        }
    } catch {
        Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to sync reusable policy settings for template $($Settings.TemplateList.value): $($_.Exception.Message)" -sev 'Error'
        Write-Host "IntuneTemplate: $($Settings.TemplateList.value) - Failed to sync reusable policy settings. Skipping this template."
        return $true
    }
    Write-Information "[IntuneTemplate][$Tenant] ReusableSync: $([int]($sw.Elapsed - $lap).TotalMilliseconds)ms"
    $lap = $sw.Elapsed

    $displayname = $Template.Displayname
    $description = $Template.Description
    $RawJSON = $rawJsonFromTemplate
    $TemplateType = $Template.Type

    # Fallback: infer type from RAWJson content when stored template has no Type
    if (-not $TemplateType) {
        try {
            $parsedRaw = $rawJsonFromTemplate | ConvertFrom-Json -ErrorAction SilentlyContinue
            $odataType = $parsedRaw.'@odata.type'
            $TemplateType = if ($null -ne $parsedRaw.settings -and $null -ne $parsedRaw.technologies) { 'Catalog' }
                elseif ($null -ne $parsedRaw.scheduledActionsForRule -or $odataType -match 'CompliancePolicy') { 'deviceCompliancePolicies' }
                elseif ($odataType -match 'windowsDriverUpdateProfile') { 'windowsDriverUpdateProfiles' }
                elseif ($odataType -match 'ManagedApp|managedAppProtection') { 'AppProtection' }
                elseif ($odataType -match 'deviceConfiguration|#microsoft\.graph\.\w+Configuration$') { 'Device' }
                else { $null }
        } catch {
            $TemplateType = $null
        }
        if ($TemplateType) {
            Write-Information "[IntuneTemplate][$Tenant] Inferred template type '$TemplateType' from content for '$displayname'"
        } else {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Intune Template '$displayname' has no Type and type could not be inferred. Re-import the template to fix." -sev 'Error'
            return $true
        }
    }

    $AssignmentsMatch = $null
    try {
        $ExistingPolicy = Get-CIPPIntunePolicy -tenantFilter $Tenant -DisplayName $displayname -TemplateType $TemplateType
        if ($ExistingPolicy -and $Settings.verifyAssignments -eq $true) {
            Write-Information "Verifying assignments for tenant $Tenant"
            $ExistingAssignments = Get-CIPPIntunePolicyAssignments -PolicyId $ExistingPolicy.id -TemplateType $TemplateType -TenantFilter $Tenant -ExistingPolicy $ExistingPolicy
            $AssignmentsMatch = Compare-CIPPIntuneAssignments -ExistingAssignments $ExistingAssignments -ExpectedAssignTo $Settings.AssignTo -ExpectedCustomGroup $Settings.customGroup -ExpectedExcludeGroup $Settings.excludeGroup -ExpectedAssignmentFilter $Settings.assignmentFilter -ExpectedAssignmentFilterType $Settings.assignmentFilterType -TenantFilter $Tenant

            Write-Information "AssignmentsMatch for tenant $($Tenant): $AssignmentsMatch"
        }
    } catch {
        $ExistingPolicy = $null
    }
    Write-Information "[IntuneTemplate][$Tenant] GetPolicy '$displayname' ($TemplateType): $([int]($sw.Elapsed - $lap).TotalMilliseconds)ms"
    $lap = $sw.Elapsed

    if ($ExistingPolicy) {
        try {
            $RawJSON = Get-CIPPTextReplacement -Text $RawJSON -TenantFilter $Tenant
            $JSONExistingPolicy = $ExistingPolicy.cippconfiguration | ConvertFrom-Json
            $JSONTemplate = $RawJSON | ConvertFrom-Json
            $Compare = Compare-CIPPIntuneObject -ReferenceObject $JSONTemplate -DifferenceObject $JSONExistingPolicy -compareType $TemplateType -ErrorAction SilentlyContinue
        } catch {
        }
        Write-Information "[IntuneTemplate][$Tenant] Compare '$displayname': $([int]($sw.Elapsed - $lap).TotalMilliseconds)ms"
        $lap = $sw.Elapsed
    } else {
        $compare = [pscustomobject]@{
            MatchFailed = $true
            Difference  = 'This policy does not exist in Intune.'
        }
    }
    $CompareResult = [PSCustomObject]@{
        MatchFailed          = [bool]$Compare
        displayname          = $displayname
        description          = $description
        compare              = $Compare
        rawJSON              = $RawJSON
        templateType         = $TemplateType
        assignTo             = $Settings.AssignTo
        excludeGroup         = $Settings.excludeGroup
        remediate            = $Settings.remediate
        alert                = $Settings.alert
        report               = $Settings.report
        existingPolicyId     = $ExistingPolicy.id
        templateId           = $Settings.TemplateList.value
        customGroup          = $Settings.customGroup
        assignmentFilter     = $Settings.assignmentFilter
        assignmentFilterType = $Settings.assignmentFilterType
        AssignmentsMatch     = $AssignmentsMatch
    }

    if ($Settings.remediate) {
        try {
            $CompareResult.customGroup ? ($CompareResult.AssignTo = $CompareResult.customGroup) : $null

            $PolicyParams = @{
                TemplateType = $CompareResult.templateType
                Description  = $CompareResult.description
                DisplayName  = $CompareResult.displayname
                RawJSON      = $CompareResult.rawJSON
                AssignTo     = $CompareResult.AssignTo
                ExcludeGroup = $CompareResult.excludeGroup
                tenantFilter = $Tenant
            }

            # Add assignment filter if specified
            if ($CompareResult.assignmentFilter) {
                $PolicyParams.AssignmentFilterName = $CompareResult.assignmentFilter
                $PolicyParams.AssignmentFilterType = $CompareResult.assignmentFilterType ?? 'include'
            }

            Set-CIPPIntunePolicy @PolicyParams
            # Remediation succeeded — accept Graph return and update state so report reflects it
            $CompareResult.compare = $null
            $CompareResult.MatchFailed = $false
            $CompareResult.AssignmentsMatch = $true
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to create or update Intune Template $($CompareResult.displayname), Error: $ErrorMessage" -sev 'Error'
            Write-Information "IntuneTemplate: $($CompareResult.displayname) - Failed to remediate. Error: $ErrorMessage"
        }
        Write-Information "[IntuneTemplate][$Tenant] Remediate '$displayname': $([int]($sw.Elapsed - $lap).TotalMilliseconds)ms"
        $lap = $sw.Elapsed
    }

    if ($Settings.alert) {
        $AlertObj = $CompareResult | Select-Object -Property displayname, description, compare, assignTo, excludeGroup, existingPolicyId, AssignmentsMatch
        $AssignmentsDiffer = $Settings.verifyAssignments -and ($null -ne $CompareResult.AssignmentsMatch -and -not $CompareResult.AssignmentsMatch)
        $HasDifference = $CompareResult.compare -or $AssignmentsDiffer
        if ($HasDifference) {
            $Message = if ($CompareResult.compare) {
                "Template $($CompareResult.displayname) does not match the expected configuration."
            } elseif ($AssignmentsDiffer) {
                "Template $($CompareResult.displayname) has incorrect assignments."
            } else {
                "Template $($CompareResult.displayname) does not match the expected configuration."
            }
            Write-StandardsAlert -message $Message -object $AlertObj -tenant $Tenant -standardName 'IntuneTemplate' -standardId $Settings.templateId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "$Message We've generated an alert" -sev info
        } else {
            if ($CompareResult.existingPolicyId) {
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Template $($CompareResult.displayname) has the correct configuration." -sev Info
            } else {
                Write-StandardsAlert -message "Template $($CompareResult.displayname) is missing." -object $AlertObj -tenant $Tenant -standardName 'IntuneTemplate' -standardId $Settings.templateId
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Template $($CompareResult.displayname) is missing." -sev info
            }
        }
    }

    if ($Settings.report -or $Settings.remediate) {
        $id = $CompareResult.templateId

        $CurrentValue = @{
            displayName = $CompareResult.displayname
            description = $CompareResult.description
            isCompliant = if ($CompareResult.compare) { $false } else { $true }
        }
        $ExpectedValue = @{
            displayName = $CompareResult.displayname
            description = $CompareResult.description
            isCompliant = $true
        }

        if ($Settings.verifyAssignments) {
            $CurrentValue['isAssigned'] = if ($null -ne $CompareResult.AssignmentsMatch) { $CompareResult.AssignmentsMatch } else { $false }
            $ExpectedValue['isAssigned'] = $true
        }
        Set-CIPPStandardsCompareField -FieldName "standards.IntuneTemplate.$id" -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        #Add-CIPPBPAField -FieldName "policy-$id" -FieldValue $Compare -StoreAs bool -Tenant $tenant
    }

    $sw.Stop()
    Write-Information "[IntuneTemplate][$Tenant] TOTAL '$displayname': $([int]$sw.Elapsed.TotalMilliseconds)ms"
}

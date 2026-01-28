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
            {"type":"autoComplete","multiple":false,"required":false,"creatable":false,"name":"TemplateList-Tags","label":"Or select a package of Intune Templates","api":{"queryKey":"ListIntuneTemplates-tag-autcomplete","url":"/api/ListIntuneTemplates?mode=Tag","labelField":"label","valueField":"value","addedField":{"templates":"templates"}}}
            {"name":"AssignTo","label":"Who should this template be assigned to?","type":"radio","options":[{"label":"Do not assign","value":"On"},{"label":"Assign to all users","value":"allLicensedUsers"},{"label":"Assign to all devices","value":"AllDevices"},{"label":"Assign to all users and devices","value":"AllDevicesAndUsers"},{"label":"Assign to Custom Group","value":"customGroup"}]}
            {"type":"textField","required":false,"name":"customGroup","label":"Enter the custom group name if you selected 'Assign to Custom Group'. Wildcards are allowed."}
            {"name":"excludeGroup","label":"Exclude Groups","type":"textField","required":false,"helpText":"Enter the group name(s) to exclude from the assignment. Wildcards are allowed. Multiple group names are comma-seperated."}
            {"type":"textField","required":false,"name":"assignmentFilter","label":"Assignment Filter Name (Optional)","helpText":"Enter the assignment filter name to apply to this policy assignment. Wildcards are allowed."}
            {"name":"assignmentFilterType","label":"Assignment Filter Mode (Optional)","type":"radio","required":false,"helpText":"Choose whether to include or exclude devices matching the filter. Only applies if you specified a filter name above. Defaults to Include if not specified.","options":[{"label":"Include - Assign to devices matching the filter","value":"include"},{"label":"Exclude - Assign to devices NOT matching the filter","value":"exclude"}]}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    param($Tenant, $Settings)
    $TestResult = Test-CIPPStandardLicense -StandardName 'IntuneTemplate_general' -TenantFilter $Tenant -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1')

    if ($TestResult -eq $false) {
        #writing to each item that the license is not present.
        foreach ($Template in $settings.TemplateList) {
            Set-CIPPStandardsCompareField -FieldName "standards.IntuneTemplate.$($Template.value)" -FieldValue 'This tenant does not have the required license for this standard.' -Tenant $Tenant
        }
        return $true
    } #we're done.
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'IntuneTemplate'"
    $Request = @{body = $null }
    $CompareList = foreach ($Template in $Settings) {
        $Request.body = (Get-CIPPAzDataTableEntity @Table -Filter $Filter | Where-Object -Property RowKey -Like "$($Template.TemplateList.value)*").JSON | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($null -eq $Request.body) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to find template $($Template.TemplateList.value). Has this Intune Template been deleted?" -sev 'Error'
            continue
        }

        $displayname = $request.body.Displayname
        $description = $request.body.Description
        $RawJSON = $Request.body.RawJSON
        try {
            $ExistingPolicy = Get-CIPPIntunePolicy -tenantFilter $Tenant -DisplayName $displayname -TemplateType $Request.body.Type
        } catch {
        }
        if ($ExistingPolicy) {
            try {
                $RawJSON = Get-CIPPTextReplacement -Text $RawJSON -TenantFilter $Tenant
                $JSONExistingPolicy = $ExistingPolicy.cippconfiguration | ConvertFrom-Json
                $JSONTemplate = $RawJSON | ConvertFrom-Json
                $Compare = Compare-CIPPIntuneObject -ReferenceObject $JSONTemplate -DifferenceObject $JSONExistingPolicy -compareType $Request.body.Type -ErrorAction SilentlyContinue
            } catch {
            }
        } else {
            $compare = [pscustomobject]@{
                MatchFailed = $true
                Difference  = 'This policy does not exist in Intune.'
            }
        }
        if ($Compare) {
            [PSCustomObject]@{
                MatchFailed          = $true
                displayname          = $displayname
                description          = $description
                compare              = $Compare
                rawJSON              = $RawJSON
                body                 = $Request.body
                assignTo             = $Template.AssignTo
                excludeGroup         = $Template.excludeGroup
                remediate            = $Template.remediate
                alert                = $Template.alert
                report               = $Template.report
                existingPolicyId     = $ExistingPolicy.id
                templateId           = $Template.TemplateList.value
                customGroup          = $Template.customGroup
                assignmentFilter     = $Template.assignmentFilter
                assignmentFilterType = $Template.assignmentFilterType
            }
        } else {
            [PSCustomObject]@{
                MatchFailed          = $false
                displayname          = $displayname
                description          = $description
                compare              = $false
                rawJSON              = $RawJSON
                body                 = $Request.body
                assignTo             = $Template.AssignTo
                excludeGroup         = $Template.excludeGroup
                remediate            = $Template.remediate
                alert                = $Template.alert
                report               = $Template.report
                existingPolicyId     = $ExistingPolicy.id
                templateId           = $Template.TemplateList.value
                customGroup          = $Template.customGroup
                assignmentFilter     = $Template.assignmentFilter
                assignmentFilterType = $Template.assignmentFilterType
            }
        }
    }

    if ($true -in $Settings.remediate) {
        foreach ($TemplateFile in $CompareList | Where-Object -Property remediate -EQ $true) {
            try {
                $TemplateFile.customGroup ? ($TemplateFile.AssignTo = $TemplateFile.customGroup) : $null

                $PolicyParams = @{
                    TemplateType = $TemplateFile.body.Type
                    Description  = $TemplateFile.description
                    DisplayName  = $TemplateFile.displayname
                    RawJSON      = $templateFile.rawJSON
                    AssignTo     = $TemplateFile.AssignTo
                    ExcludeGroup = $TemplateFile.excludeGroup
                    tenantFilter = $Tenant
                }

                # Add assignment filter if specified
                if ($TemplateFile.assignmentFilter) {
                    $PolicyParams.AssignmentFilterName = $TemplateFile.assignmentFilter
                    $PolicyParams.AssignmentFilterType = $TemplateFile.assignmentFilterType ?? 'include'
                }

                Set-CIPPIntunePolicy @PolicyParams
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to create or update Intune Template $($TemplateFile.displayname), Error: $ErrorMessage" -sev 'Error'
            }
        }

    }

    if ($true -in $Settings.alert) {
        foreach ($Template in $CompareList | Where-Object -Property alert -EQ $true) {
            $AlertObj = $Template | Select-Object -Property displayname, description, compare, assignTo, excludeGroup, existingPolicyId
            if ($Template.compare) {
                Write-StandardsAlert -message "Template $($Template.displayname) does not match the expected configuration." -object $AlertObj -tenant $Tenant -standardName 'IntuneTemplate' -standardId $Settings.templateId
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Template $($Template.displayname) does not match the expected configuration. We've generated an alert" -sev info
            } else {
                if ($Template.ExistingPolicyId) {
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Template $($Template.displayname) has the correct configuration." -sev Info
                } else {
                    Write-StandardsAlert -message "Template $($Template.displayname) is missing." -object $AlertObj -tenant $Tenant -standardName 'IntuneTemplate' -standardId $Settings.templateId
                    Write-LogMessage -API 'Standards' -tenant $Tenant -message "Template $($Template.displayname) is missing." -sev info
                }
            }
        }
    }

    if ($true -in $Settings.report) {
        foreach ($Template in $CompareList | Where-Object { $_.report -eq $true -or $_.remediate -eq $true }) {
            $id = $Template.templateId

            $CurrentValue = @{
                displayName = $Template.displayname
                description = $Template.description
                isCompliant = if ($Template.compare) { $false } else { $true }
            }
            $ExpectedValue = @{
                displayName = $Template.displayname
                description = $Template.description
                isCompliant = $true
            }
            Set-CIPPStandardsCompareField -FieldName "standards.IntuneTemplate.$id" -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
        }
        #Add-CIPPBPAField -FieldName "policy-$id" -FieldValue $Compare -StoreAs bool -Tenant $tenant
    }
}

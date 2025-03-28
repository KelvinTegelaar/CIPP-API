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

        IMPACT
            High Impact
        ADDEDDATE
            2023-12-30
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"name":"TemplateList","label":"Select Intune Template","api":{"url":"/api/ListIntuneTemplates","labelField":"Displayname","valueField":"GUID","queryKey":"languages"}}
            {"name":"AssignTo","label":"Who should this template be assigned to?","type":"radio","options":[{"label":"Do not assign","value":"On"},{"label":"Assign to all users","value":"allLicensedUsers"},{"label":"Assign to all devices","value":"AllDevices"},{"label":"Assign to all users and devices","value":"AllDevicesAndUsers"},{"label":"Assign to Custom Group","value":"customGroup"}]}
            {"type":"textField","required":false,"name":"customGroup","label":"Enter the custom group name if you selected 'Assign to Custom Group'. Wildcards are allowed."}
            {"name":"ExcludeGroup","label":"Exclude Groups","type":"textField","required":false,"helpText":"Enter the group name to exclude from the assignment. Wildcards are allowed."}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/
    #>
    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'intuneTemplate'
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'IntuneTemplate'"
    $Request = @{body = $null }

    $CompareList = foreach ($Template in $Settings) {
        $Request.body = (Get-CIPPAzDataTableEntity @Table -Filter $Filter | Where-Object -Property RowKey -Like "$($Template.TemplateList.value)*").JSON | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($Request.body -eq $null) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to find template $($Template.TemplateList.value). Has this Intune Template been deleted?" -sev 'Error'
            continue
        }
        $displayname = $request.body.Displayname
        $description = $request.body.Description
        $RawJSON = $Request.body.RawJSON
        $ExistingPolicy = Get-CIPPIntunePolicy -tenantFilter $Tenant -DisplayName $displayname -TemplateType $Request.body.Type
        if ($ExistingPolicy) {
            $RawJSON = Get-CIPPTextReplacement -Text $RawJSON -TenantFilter $Tenant
            $JSONExistingPolicy = $ExistingPolicy.cippconfiguration | ConvertFrom-Json
            $JSONTemplate = $RawJSON | ConvertFrom-Json
            $Compare = Compare-CIPPIntuneObject -ReferenceObject $JSONTemplate -DifferenceObject $JSONExistingPolicy -compareType $Request.body.Type
        }
        if ($Compare) {
            [PSCustomObject]@{
                MatchFailed      = $true
                displayname      = $displayname
                description      = $description
                compare          = $Compare
                rawJSON          = $RawJSON
                body             = $Request.body
                assignTo         = $Template.AssignTo
                excludeGroup     = $Template.excludeGroup
                remediate        = $Template.remediate
                existingPolicyId = $ExistingPolicy.id
                templateId       = $Template.TemplateList.value
            }
        } else {
            [PSCustomObject]@{
                MatchFailed      = $false
                displayname      = $displayname
                description      = $description
                compare          = $false
                rawJSON          = $RawJSON
                body             = $Request.body
                assignTo         = $Template.AssignTo
                excludeGroup     = $Template.excludeGroup
                remediate        = $Template.remediate
                existingPolicyId = $ExistingPolicy.id
                templateId       = $Template.TemplateList.value
            }
        }
    }

    If ($true -in $Settings.remediate) {
        Write-Host 'starting template deploy'
        foreach ($TemplateFile in $CompareList | Where-Object -Property remediate -EQ $true) {
            Write-Host "working on template deploy: $($Template.displayname)"
            try {
                $TemplateFile.customGroup ? ($TemplateFile.AssignTo = $TemplateFile.customGroup) : $null
                Set-CIPPIntunePolicy -TemplateType $TemplateFile.body.Type -Description $TemplateFile.description -DisplayName $TemplateFile.displayname -RawJSON $templateFile.rawJSON -AssignTo $TemplateFile.AssignTo -ExcludeGroup $TemplateFile.excludeGroup -tenantFilter $Tenant
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to create or update Intune Template $PolicyName, Error: $ErrorMessage" -sev 'Error'
            }
        }

    }

    if ($Settings.alert) {
        foreach ($Template in $CompareList) {
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

    if ($Settings.report) {
        foreach ($Template in $CompareList) {
            $id = $Template.templateId
            $CompareObj = $Template.compare
            $state = $CompareObj ? $CompareObj : $true
            Set-CIPPStandardsCompareField -FieldName "standards.IntuneTemplate.$id" -FieldValue $state -TenantFilter $Tenant
        }
        Add-CIPPBPAField -FieldName "policy-$id" -FieldValue $Compare -StoreAs bool -Tenant $tenant
    }
}

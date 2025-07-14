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
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"name":"TemplateList","label":"Select Intune Template","api":{"url":"/api/ListIntuneTemplates","labelField":"Displayname","valueField":"GUID","queryKey":"languages"}}
            {"name":"AssignTo","label":"Who should this template be assigned to?","type":"radio","options":[{"label":"Do not assign","value":"On"},{"label":"Assign to all users","value":"allLicensedUsers"},{"label":"Assign to all devices","value":"AllDevices"},{"label":"Assign to all users and devices","value":"AllDevicesAndUsers"},{"label":"Assign to Custom Group","value":"customGroup"}]}
            {"type":"textField","required":false,"name":"customGroup","label":"Enter the custom group name if you selected 'Assign to Custom Group'. Wildcards are allowed."}
            {"name":"excludeGroup","label":"Exclude Groups","type":"textField","required":false,"helpText":"Enter the group name to exclude from the assignment. Wildcards are allowed."}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards
    #>
    param($Tenant, $Settings)
    Test-CIPPStandardLicense -StandardName 'IntuneTemplate' -TenantFilter $Tenant -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1')
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'intuneTemplate'
    $Table = Get-CippTable -tablename 'templates'
    $Filter = "PartitionKey eq 'IntuneTemplate'"
    $Request = @{body = $null }
    Write-Host "IntuneTemplate: Starting process. Settings are: $($Settings | ConvertTo-Json -Compress)"
    $CompareList = foreach ($Template in $Settings) {
        Write-Host "IntuneTemplate: $($Template.TemplateList.value) - Trying to find template"
        $Request.body = (Get-CIPPAzDataTableEntity @Table -Filter $Filter | Where-Object -Property RowKey -Like "$($Template.TemplateList.value)*").JSON | ConvertFrom-Json -ErrorAction SilentlyContinue
        if ($null -eq $Request.body) {
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to find template $($Template.TemplateList.value). Has this Intune Template been deleted?" -sev 'Error'
            continue
        }
        Write-Host "IntuneTemplate: $($Template.TemplateList.value) - Got template."

        $displayname = $request.body.Displayname
        $description = $request.body.Description
        $RawJSON = $Request.body.RawJSON
        try {
            Write-Host "IntuneTemplate: $($Template.TemplateList.value) - Grabbing existing Policy"
            $ExistingPolicy = Get-CIPPIntunePolicy -tenantFilter $Tenant -DisplayName $displayname -TemplateType $Request.body.Type
        } catch {
            Write-Host "IntuneTemplate: $($Template.TemplateList.value) - Failed to get existing."
        }
        if ($ExistingPolicy) {
            try {
                Write-Host "IntuneTemplate: $($Template.TemplateList.value) - Found existing policy."
                $RawJSON = Get-CIPPTextReplacement -Text $RawJSON -TenantFilter $Tenant
                Write-Host "IntuneTemplate: $($Template.TemplateList.value) - Grabbing JSON existing."
                $JSONExistingPolicy = $ExistingPolicy.cippconfiguration | ConvertFrom-Json
                Write-Host "IntuneTemplate: $($Template.TemplateList.value) - Got existing JSON. Converting RawJSON to Template"
                $JSONTemplate = $RawJSON | ConvertFrom-Json
                Write-Host "IntuneTemplate: $($Template.TemplateList.value) - Converted RawJSON to Template."
                Write-Host "IntuneTemplate: $($Template.TemplateList.value) - Comparing JSON."
                $Compare = Compare-CIPPIntuneObject -ReferenceObject $JSONTemplate -DifferenceObject $JSONExistingPolicy -compareType $Request.body.Type -ErrorAction SilentlyContinue
            } catch {
                Write-Host "The compare failed. The error was: $($_.Exception.Message)"
            }
            Write-Host "IntuneTemplate: $($Template.TemplateList.value) - Compared JSON: $($Compare | ConvertTo-Json -Compress)"
        } else {
            Write-Host "IntuneTemplate: $($Template.TemplateList.value) - No existing policy found."
        }
        if ($Compare) {
            Write-Host "IntuneTemplate: $($Template.TemplateList.value) - Compare found differences."
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
                alert            = $Template.alert
                report           = $Template.report
                existingPolicyId = $ExistingPolicy.id
                templateId       = $Template.TemplateList.value
                customGroup      = $Template.customGroup
            }
        } else {
            Write-Host "IntuneTemplate: $($Template.TemplateList.value) - No differences found."
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
                alert            = $Template.alert
                report           = $Template.report
                existingPolicyId = $ExistingPolicy.id
                templateId       = $Template.TemplateList.value
                customGroup      = $Template.customGroup
            }
        }
    }

    If ($true -in $Settings.remediate) {
        Write-Host 'starting template deploy'
        foreach ($TemplateFile in $CompareList | Where-Object -Property remediate -EQ $true) {
            Write-Host "working on template deploy: $($TemplateFile.displayname)"
            try {
                $TemplateFile.customGroup ? ($TemplateFile.AssignTo = $TemplateFile.customGroup) : $null
                Set-CIPPIntunePolicy -TemplateType $TemplateFile.body.Type -Description $TemplateFile.description -DisplayName $TemplateFile.displayname -RawJSON $templateFile.rawJSON -AssignTo $TemplateFile.AssignTo -ExcludeGroup $TemplateFile.excludeGroup -tenantFilter $Tenant
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to create or update Intune Template $($TemplateFile.displayname), Error: $ErrorMessage" -sev 'Error'
            }
        }

    }

    if ($true -in $Settings.alert) {
        foreach ($Template in $CompareList | Where-Object -Property alert -EQ $true) {
            Write-Host "working on template alert: $($Template.displayname)"
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
        foreach ($Template in $CompareList | Where-Object -Property report -EQ $true) {
            Write-Host "working on template report: $($Template.displayname)"
            $id = $Template.templateId
            $CompareObj = $Template.compare
            $state = $CompareObj ? $CompareObj : $true
            Set-CIPPStandardsCompareField -FieldName "standards.IntuneTemplate.$id" -FieldValue $state -TenantFilter $Tenant
        }
        #Add-CIPPBPAField -FieldName "policy-$id" -FieldValue $Compare -StoreAs bool -Tenant $tenant
    }
}

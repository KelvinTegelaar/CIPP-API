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
    $Request.body = (Get-CIPPAzDataTableEntity @Table -Filter $Filter | Where-Object -Property RowKey -Like "$($Settings.TemplateList.value)*").JSON | ConvertFrom-Json
    $displayname = $request.body.Displayname
    $description = $request.body.Description
    $RawJSON = $Request.body.RawJSON
    $ExistingPolicy = Get-CIPPIntunePolicy -tenantFilter $Tenant -DisplayName $displayname -TemplateType $Request.body.Type
    if ($ExistingPolicy) {
        $JSONExistingPolicy = $ExistingPolicy.cippconfiguration | ConvertFrom-Json
        $JSONTemplate = $RawJSON | ConvertFrom-Json
        $Compare = Compare-CIPPIntuneObject -ReferenceObject $JSONTemplate -DifferenceObject $JSONExistingPolicy -compareType $Request.body.Type
    }
    If ($Settings.remediate -eq $true) {
        Write-Host 'starting template deploy'
        Write-Host "The full settings are $($Settings | ConvertTo-Json)"
        try {
            $Settings.customGroup ? ($Settings.AssignTo = $Settings.customGroup) : $null
            Set-CIPPIntunePolicy -TemplateType $Request.body.Type -Description $description -DisplayName $displayname -RawJSON $RawJSON -AssignTo $Settings.AssignTo -ExcludeGroup $Settings.excludeGroup -tenantFilter $Tenant
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to create or update Intune Template $displayname, Error: $ErrorMessage" -sev 'Error'
        }

    }

    if ($Settings.alert) {
        #Replace the alert method used in standards with a prettier one, link to the report/template, link to a compare. extended table. etc
        if ($compare) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Policy $($displayname) does not match the expected configuration." -sev Alert
        } else {
            $ExistingPolicy ? (Write-LogMessage -API 'Standards' -tenant $Tenant -message "Policy $($displayname) has the correct configuration." -sev Info) : (Write-LogMessage -API 'Standards' -tenant $Tenant -message "Policy $($displayname) is missing." -sev Alert)
        }
    }

    if ($Settings.report) {
        #think about how to store this.
        Add-CIPPBPAField -FieldName "policy-$displayname" -FieldValue $Compare -StoreAs bool -Tenant $tenant
    }
}

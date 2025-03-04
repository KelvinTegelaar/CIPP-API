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

    If ($Settings.remediate -eq $true) {

        Write-Host 'starting template deploy'
        Write-Host "The full settings are $($Settings | ConvertTo-Json)"
        foreach ($Template in $Settings) {
            Write-Host "working on template deploy: $($Template | ConvertTo-Json)"
            try {
                $Table = Get-CippTable -tablename 'templates'
                $Filter = "PartitionKey eq 'IntuneTemplate'"
                $Request = @{body = $null }
                $Request.body = (Get-CIPPAzDataTableEntity @Table -Filter $Filter | Where-Object -Property RowKey -Like "$($Template.TemplateList.value)*").JSON | ConvertFrom-Json
                $displayname = $request.body.Displayname
                $description = $request.body.Description
                $RawJSON = $Request.body.RawJSON
                $Template.customGroup ? ($Template.AssignTo = $Template.customGroup) : $null
                Set-CIPPIntunePolicy -TemplateType $Request.body.Type -Description $description -DisplayName $displayname -RawJSON $RawJSON -AssignTo $Template.AssignTo -ExcludeGroup $Template.excludeGroup -tenantFilter $Tenant

            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to create or update Intune Template $displayname, Error: $ErrorMessage" -sev 'Error'
            }
        }
    }
}

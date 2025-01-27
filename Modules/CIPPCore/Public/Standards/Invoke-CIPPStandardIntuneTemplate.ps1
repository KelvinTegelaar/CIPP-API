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
            High
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"name":"TemplateList","label":"Select Intune Template","api":{"url":"/api/ListIntuneTemplates","labelField":"Displayname","valueField":"GUID","queryKey":"languages"}}
            {"name":"AssignTo","label":"Who should this template be assigned to?","type":"radio","options":[{"label":"Do not assign","value":"On"},{"label":"Assign to all users","value":"allLicensedUsers"},{"label":"Assign to all devices","value":"AllDevices"},{"label":"Assign to all users and devices","value":"AllDevicesAndUsers"},{"label":"Assign to Custom Group","value":"customGroup"}]}
            {"type":"textField","required":false,"name":"customGroup","label":"Enter the custom group name if you selected 'Assign to Custom Group'. Wildcards are allowed."}
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/list-standards/
    #>
    param($Tenant, $Settings)
    ##$Rerun -Type Standard -Tenant $Tenant -Settings $Settings 'intuneTemplate'

    If ($Settings.remediate -eq $true) {

        Write-Host 'starting template deploy'
        $APINAME = 'Standards'
        foreach ($Template in $Settings.TemplateList) {
            Write-Host "working on template deploy: $($Template | ConvertTo-Json)"
            try {
                $Table = Get-CippTable -tablename 'templates'
                $Filter = "PartitionKey eq 'IntuneTemplate'"
                $Request = @{body = $null }
                $Request.body = (Get-CIPPAzDataTableEntity @Table -Filter $Filter | Where-Object -Property RowKey -Like "$($template.value)*").JSON | ConvertFrom-Json
                $displayname = $request.body.Displayname
                $description = $request.body.Description
                $RawJSON = $Request.body.RawJSON
                Set-CIPPIntunePolicy -TemplateType $Request.body.Type -Description $description -DisplayName $displayname -RawJSON $RawJSON -AssignTo $Template.AssignTo -tenantFilter $Tenant

            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to create or update Intune Template $PolicyName, Error: $ErrorMessage" -sev 'Error'
            }
        }
    }
}

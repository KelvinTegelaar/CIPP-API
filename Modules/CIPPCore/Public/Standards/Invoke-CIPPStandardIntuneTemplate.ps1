function Invoke-CIPPStandardIntuneTemplate {
    <#
    .FUNCTIONALITY
    Internal
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
                $TemplateTypeURL = $Request.body.Type

                Set-CIPPIntunePolicy -TemplateType $Request.body.Type -Description $description -DisplayName $displayname -RawJSON $RawJSON -AssignTo $Template.AssignedTo -tenantFilter $Tenant

                #Legacy assign, only required for older templates.
                if ($Settings.AssignTo) {
                    Write-Host "Assigning Policy to $($Settings.AssignTo) the create ID is $($CreateRequest)"
                    if ($Settings.AssignTo -eq 'customGroup') { $Settings.AssignTo = $Settings.customGroup }
                    if ($ExistingID) {
                        Set-CIPPAssignedPolicy -PolicyId $ExistingID.id -TenantFilter $tenant -GroupName $Settings.AssignTo -Type $TemplateTypeURL
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully updated Intune Template $PolicyName policy for $($Tenant)" -sev 'Info'
                    } else {
                        Set-CIPPAssignedPolicy -PolicyId $CreateRequest.id -TenantFilter $tenant -GroupName $Settings.AssignTo -Type $TemplateTypeURL
                        Write-LogMessage -API 'Standards' -tenant $tenant -message "Successfully created Intune Template $PolicyName policy for $($Tenant)" -sev 'Info'
                    }
                }

            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to create or update Intune Template $PolicyName, Error: $ErrorMessage" -sev 'Error'
            }
        }
    }
}

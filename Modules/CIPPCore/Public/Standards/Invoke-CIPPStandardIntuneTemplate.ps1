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
                Set-CIPPIntunePolicy -TemplateType $Request.body.Type -Description $description -DisplayName $displayname -RawJSON $RawJSON -AssignTo $Template.AssignTo -tenantFilter $Tenant

            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                Write-LogMessage -API 'Standards' -tenant $tenant -message "Failed to create or update Intune Template $PolicyName, Error: $ErrorMessage" -sev 'Error'
            }
        }
    }
}

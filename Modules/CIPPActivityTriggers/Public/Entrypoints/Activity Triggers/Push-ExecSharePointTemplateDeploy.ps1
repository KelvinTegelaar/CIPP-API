function Push-ExecSharePointTemplateDeploy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .DESCRIPTION
        Queue worker that deploys a SharePoint provisioning template to a single tenant.
        Queued per tenant by Invoke-ExecSharePointTemplate (Action=Deploy). Progress is
        written to the shared CacheAsyncDeployments status rows so the frontend can poll
        it live via Action=DeployStatus.
    #>
    param($Item)

    try {
        $Item = $Item | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $TemplateId = $Item.TemplateId
        $DeploymentId = $Item.DeploymentId
        if (-not $TemplateId) {
            Write-LogMessage -message 'No SharePoint template specified' -tenant $Item.Tenant -API 'Deploy SharePoint Template' -sev Error
            return $false
        }

        $Table = Get-CIPPTable -TableName 'templates'
        $Template = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'SharePointTemplate' and RowKey eq '$TemplateId'"
        if (-not $Template) {
            Write-LogMessage -message "SharePoint template $TemplateId not found" -tenant $Item.Tenant -API 'Deploy SharePoint Template' -sev Error
            if ($DeploymentId) {
                Set-CIPPAsyncDeploymentStatus -JobId $DeploymentId -Name $Item.Tenant -Status 'failed' -Logs "Template $TemplateId not found"
            }
            return $false
        }

        if ($DeploymentId) {
            Set-CIPPAsyncDeploymentStatus -JobId $DeploymentId -Name $Item.Tenant -Status 'running'
        }

        $TemplateData = $Template.JSON | ConvertFrom-Json
        $Results = Invoke-CIPPSharePointTemplateDeploy -TemplateData $TemplateData -SiteOwner $Item.SiteOwner -TenantFilter $Item.Tenant -DeploymentId $DeploymentId
        foreach ($Result in $Results) {
            Write-Information $Result
        }

        # Overall verdict: failed when any step failed, otherwise succeeded.
        if ($DeploymentId) {
            $Row = Get-CIPPAsyncDeployment -JobId $DeploymentId | Where-Object { $_.Name -eq $Item.Tenant }
            $FinalStatus = 'succeeded'
            if (@($Row.Steps | Where-Object { $_.Status -eq 'failed' }).Count -gt 0) { $FinalStatus = 'failed' }
            Set-CIPPAsyncDeploymentStatus -JobId $DeploymentId -Name $Item.Tenant -Status $FinalStatus -Logs ($Results -join "`n")
        }
        return $true
    } catch {
        Write-LogMessage -message "Error deploying SharePoint template to tenant $($Item.Tenant) - $($_.Exception.Message)" -tenant $Item.Tenant -API 'Deploy SharePoint Template' -sev Error
        if ($Item.DeploymentId) {
            Set-CIPPAsyncDeploymentStatus -JobId $Item.DeploymentId -Name $Item.Tenant -Status 'failed' -Logs $_.Exception.Message
        }
        Write-Error $_.Exception.Message
    }
}

function Push-ExecSharePointTemplateDeploy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .DESCRIPTION
        Queue worker that deploys a SharePoint provisioning template to a single tenant.
        Queued per tenant by Invoke-ExecSharePointTemplate (Action=Deploy).
    #>
    param($Item)

    try {
        $Item = $Item | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $TemplateId = $Item.TemplateId
        if (-not $TemplateId) {
            Write-LogMessage -message 'No SharePoint template specified' -tenant $Item.Tenant -API 'Deploy SharePoint Template' -sev Error
            return $false
        }

        $Table = Get-CIPPTable -TableName 'templates'
        $Template = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'SharePointTemplate' and RowKey eq '$TemplateId'"
        if (-not $Template) {
            Write-LogMessage -message "SharePoint template $TemplateId not found" -tenant $Item.Tenant -API 'Deploy SharePoint Template' -sev Error
            return $false
        }

        $TemplateData = $Template.JSON | ConvertFrom-Json
        $Results = Invoke-CIPPSharePointTemplateDeploy -TemplateData $TemplateData -SiteOwner $Item.SiteOwner -TenantFilter $Item.Tenant
        foreach ($Result in $Results) {
            Write-Information $Result
        }
        return $true
    } catch {
        Write-LogMessage -message "Error deploying SharePoint template to tenant $($Item.Tenant) - $($_.Exception.Message)" -tenant $Item.Tenant -API 'Deploy SharePoint Template' -sev Error
        Write-Error $_.Exception.Message
    }
}

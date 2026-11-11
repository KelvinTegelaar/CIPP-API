function Invoke-ExecDeployGSASecurityProfileTemplate {
    <#
    .SYNOPSIS
        Deploys a Global Secure Access security profile template to tenants
    .DESCRIPTION
        Creates or updates the security profile and the filtering policies it links in each selected
        tenant, so they match the template. A tenant without a Microsoft Entra Internet Access licence,
        or where the template conflicts with existing objects, is refused and left unchanged.
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.GlobalSecureAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    # The security profile template to deploy
    $TemplateId = [string]$Request.Body.TemplateList.value
    # The tenants to deploy to
    $Tenants = @($Request.Body.tenantFilter.value).Where({ $_ })
    if (-not $TemplateId -or $Tenants.Count -eq 0) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Choose a security profile template and at least one tenant' } })
    }

    try {
        $Table = Get-CippTable -tablename 'templates'
        $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'GSASecurityProfileTemplate' and RowKey eq '$(ConvertTo-CIPPODataFilterValue -Value $TemplateId -Type String)'"
        if (-not $Row) { throw [System.Management.Automation.ItemNotFoundException]::new("Security profile template $TemplateId does not exist") }
        $ProfileTemplate = $Row.JSON | ConvertFrom-Json -Depth 20
        $PolicyTemplates = @{}
        foreach ($PolicyRow in @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'GSAFilteringPolicyTemplate'")) { $PolicyTemplates[$PolicyRow.RowKey] = $PolicyRow.JSON | ConvertFrom-Json -Depth 20 }
    } catch {
        return ([HttpResponseContext]@{ StatusCode = (Get-CippErrorStatusCode -ErrorRecord $_); Body = @{ Results = "Failed to load security profile template: $(Get-NormalizedError -Message $_.Exception.Message)" } })
    }
    if ('AllTenants' -in $Tenants) { $Tenants = @((Get-Tenants).defaultDomainName) }

    $Results = [System.Collections.Generic.List[object]]::new()
    $Failed = 0
    foreach ($Tenant in $Tenants) {
        if (-not (Get-CIPPTenantCapabilities -TenantFilter $Tenant).Entra_Premium_Internet_Access) { $Results.Add([pscustomobject]@{ state = 'error'; resultText = "$($Tenant): web content filtering needs a Microsoft Entra Internet Access licence (included in Microsoft Entra Suite), so nothing was changed" }); $Failed++; continue }
        try {
            $Sync = Sync-CIPPGSAFilteringProfile -ProfileTemplate $ProfileTemplate -PolicyTemplates $PolicyTemplates -TenantFilter $Tenant
            foreach ($Item in $Sync.Results) { $Results.Add([pscustomobject]@{ state = $Item.state; resultText = "$($Tenant): $($Item.resultText)" }) }
            if (@($Sync.Results).Count -eq 0) { $Results.Add([pscustomobject]@{ state = 'success'; resultText = "$($Tenant): security profile '$($ProfileTemplate.name)' already matches the template" }) }
            $TenantFailed = @($Sync.Results).Where({ $_.state -eq 'error' }).Count -gt 0
            if ($TenantFailed) { $Failed++ }
            Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant -message "Deployed security profile template '$($ProfileTemplate.name)' with $(@($Sync.Results).Count) change(s)" -Sev ($TenantFailed ? 'Warning' : 'Info')
        } catch {
            $Failed++
            $Results.Add([pscustomobject]@{ state = 'error'; resultText = "$($Tenant): $(Get-NormalizedError -Message $_.Exception.Message)" })
            Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant -message "Failed to deploy security profile template '$($ProfileTemplate.name)': $($_.Exception.Message)" -Sev 'Error' -LogData (Get-CippException -Exception $_)
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = Get-CippBulkStatusCode -Total $Tenants.Count -Failed $Failed
            Body       = @{ Results = @($Results) }
        })
}

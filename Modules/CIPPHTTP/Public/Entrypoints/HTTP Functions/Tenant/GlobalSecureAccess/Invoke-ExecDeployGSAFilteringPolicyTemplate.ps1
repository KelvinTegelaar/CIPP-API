function Invoke-ExecDeployGSAFilteringPolicyTemplate {
    <#
    .SYNOPSIS
        Deploys a Global Secure Access filtering policy template to tenants
    .DESCRIPTION
        Creates the filtering policy in each selected tenant, or brings the policy with the same name in
        line with the template. A filtering policy blocks or allows nothing until a security profile links
        it. A tenant without a Microsoft Entra Internet Access licence is refused and left unchanged.
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.GlobalSecureAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    # The filtering policy template to deploy
    $TemplateId = [string]$Request.Body.TemplateList.value
    # The tenants to deploy to
    $Tenants = @($Request.Body.tenantFilter.value).Where({ $_ })
    if (-not $TemplateId -or $Tenants.Count -eq 0) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Choose a filtering policy template and at least one tenant' } })
    }

    try {
        $Table = Get-CippTable -tablename 'templates'
        $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'GSAFilteringPolicyTemplate' and RowKey eq '$(ConvertTo-CIPPODataFilterValue -Value $TemplateId -Type String)'"
        if (-not $Row) { throw [System.Management.Automation.ItemNotFoundException]::new("Filtering policy template $TemplateId does not exist") }
        $Template = $Row.JSON | ConvertFrom-Json -Depth 20
    } catch {
        return ([HttpResponseContext]@{ StatusCode = (Get-CippErrorStatusCode -ErrorRecord $_); Body = @{ Results = "Failed to load filtering policy template: $(Get-NormalizedError -Message $_.Exception.Message)" } })
    }
    if ('AllTenants' -in $Tenants) { $Tenants = @((Get-Tenants).defaultDomainName) }

    $Results = [System.Collections.Generic.List[object]]::new()
    $Failed = 0
    foreach ($Tenant in $Tenants) {
        if (-not (Get-CIPPTenantCapabilities -TenantFilter $Tenant).Entra_Premium_Internet_Access) { $Results.Add([pscustomobject]@{ state = 'error'; resultText = "$($Tenant): web content filtering needs a Microsoft Entra Internet Access licence (included in Microsoft Entra Suite), so nothing was changed" }); $Failed++; continue }
        try {
            $Current = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/networkAccess/filteringPolicies?$expand=policyRules' -tenantid $Tenant -AsApp $true).Where({ $_.name -eq $Template.name }, 'First')[0]
            $null = Set-CIPPGSAFilteringPolicy -TenantFilter $Tenant -Policy $Template -Current $Current
            $Verb = $Current ? 'Updated' : 'Created'
            $Results.Add([pscustomobject]@{ state = 'success'; resultText = "$($Tenant): $Verb filtering policy '$($Template.name)'" })
            Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant -message "$Verb filtering policy '$($Template.name)' from its template" -Sev 'Info'
        } catch {
            $Failed++
            $Results.Add([pscustomobject]@{ state = 'error'; resultText = "$($Tenant): $(Get-NormalizedError -Message $_.Exception.Message)" })
            Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant -message "Failed to deploy filtering policy template '$($Template.name)': $($_.Exception.Message)" -Sev 'Error' -LogData (Get-CippException -Exception $_)
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = Get-CippBulkStatusCode -Total $Tenants.Count -Failed $Failed
            Body       = @{ Results = @($Results) }
        })
}

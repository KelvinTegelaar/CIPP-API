function Invoke-ExecSaveGSASecurityProfileTemplate {
    <#
    .SYNOPSIS
        Saves a tenant's Global Secure Access security profile as a template
    .DESCRIPTION
        Creates a security profile template from a tenant security profile. Each linked filtering
        policy reuses the filtering policy template with the same name, or gets a new one. An existing
        template that differs from the tenant policy is never overwritten: nothing is saved and the
        differences are reported. The built-in baseline profile cannot be saved.
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.GlobalSecureAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    # The id of the tenant security profile to save
    $ID = [string]$Request.Body.ID

    if ($ID -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'ID must be the id (a GUID) of the security profile' } })
    }

    $Graph = 'https://graph.microsoft.com/beta/networkAccess'
    $Results = [System.Collections.Generic.List[object]]::new()
    try {
        $FilteringProfile = New-GraphGetRequest -uri "$Graph/filteringProfiles/$($ID)?`$expand=policies(`$expand=policy)" -tenantid $TenantFilter -AsApp $true
        if ([int64]$FilteringProfile.priority -eq 65000) { throw [System.ArgumentException]::new('The baseline profile applies to all traffic in its tenant, so it cannot be saved as a template') }
        if (-not @($FilteringProfile.policies).Count) { throw [System.ArgumentException]::new("Security profile '$($FilteringProfile.name)' links no filtering policies, and a template needs at least one") }
        $TenantPolicies = @(New-GraphGetRequest -uri "$Graph/filteringPolicies?`$expand=policyRules" -tenantid $TenantFilter -AsApp $true)
        $PoliciesById = @{}
        foreach ($Policy in $TenantPolicies) { $PoliciesById[[string]$Policy.id] = $Policy }

        $Table = Get-CippTable -tablename 'templates'
        $PolicyTemplates = @{}
        $PolicyTemplateIds = @{}
        foreach ($Row in @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'GSAFilteringPolicyTemplate'")) {
            $PolicyTemplates[$Row.RowKey] = $Row.JSON | ConvertFrom-Json
            $PolicyTemplateIds[$PolicyTemplates[$Row.RowKey].name] = $Row.RowKey
        }
        foreach ($Row in @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'GSASecurityProfileTemplate'")) {
            $Other = $Row.JSON | ConvertFrom-Json
            if ($Other.name -eq $FilteringProfile.name) { throw [System.ArgumentException]::new("A security profile template named '$($FilteringProfile.name)' already exists") }
            if ([int64]$Other.priority -eq [int64]$FilteringProfile.priority) { throw [System.ArgumentException]::new("Priority $($FilteringProfile.priority) is already used by security profile template '$($Other.name)'") }
        }

        $Errors = [System.Collections.Generic.List[string]]::new()
        $NewTemplates = [System.Collections.Generic.List[string]]::new()
        $Links = foreach ($Link in @($FilteringProfile.policies)) {
            $Policy = $PoliciesById[[string]$Link.policy.id]
            if (-not $Policy) { $Errors.Add("filtering policy '$($Link.policy.name)' was not found in the tenant"); continue }
            $TemplateId = $PolicyTemplateIds[[string]$Policy.name]
            if (-not $TemplateId) {
                $Converted = ConvertTo-CIPPGSAFilteringRule -Rules $Policy.policyRules
                if ($Converted.Errors.Count) { $Errors.Add("filtering policy '$($Link.policy.name)': $($Converted.Errors -join ', ')"); continue }
                $TemplateId = (New-Guid).Guid
                $PolicyTemplates[$TemplateId] = [pscustomobject]@{ name = [string]$Policy.name; description = [string]$Policy.description; action = [string]$Policy.action; policyRules = $Converted.Rules }
                $NewTemplates.Add($TemplateId)
            }
            [ordered]@{ policy = [ordered]@{ label = [string]$Policy.name; value = $TemplateId }; priority = [int]$Link.priority; state = [string]$Link.state; loggingState = [string]$Link.loggingState }
        }
        $ProfileTemplate = [pscustomobject]@{ name = [string]$FilteringProfile.name; description = [string]$FilteringProfile.description; priority = [int]$FilteringProfile.priority; state = [string]$FilteringProfile.state; policies = @($Links) }

        $FilteringProfile.PSObject.Properties.Add([psnoteproperty]::new('kind', 'profile'))
        foreach ($Policy in $TenantPolicies) { $Policy.PSObject.Properties.Add([psnoteproperty]::new('kind', 'policy')) }
        $TenantRows = @($FilteringProfile) + $TenantPolicies
        foreach ($Finding in @(Compare-CIPPGSAFilteringProfile -ProfileTemplate $ProfileTemplate -PolicyTemplates $PolicyTemplates -TenantRows $TenantRows).Where({ $_.object -eq 'policy' -and $_.state -ne 'match' })) {
            $Errors.Add("filtering policy template '$($Finding.name)' differs from the tenant policy ($($Finding.detail))")
        }
        if ($Errors.Count) { throw [System.ArgumentException]::new("Nothing was saved: $($Errors -join '; ')") }

        foreach ($TemplateId in $NewTemplates) {
            $JSON = ConvertTo-Json -Depth 10 -Compress -InputObject $PolicyTemplates[$TemplateId]
            Add-CIPPAzDataTableEntity @Table -Force -Entity @{ PartitionKey = 'GSAFilteringPolicyTemplate'; RowKey = $TemplateId; GUID = $TemplateId; JSON = $JSON }
            $Results.Add([pscustomobject]@{ state = 'success'; resultText = "Created filtering policy template '$($PolicyTemplates[$TemplateId].name)'" })
        }
        foreach ($Link in $ProfileTemplate.policies.Where({ $_.policy.value -notin $NewTemplates })) {
            $Results.Add([pscustomobject]@{ state = 'success'; resultText = "Linked the existing filtering policy template '$($Link.policy.label)'" })
        }
        $GUID = (New-Guid).Guid
        Add-CIPPAzDataTableEntity @Table -Force -Entity @{ PartitionKey = 'GSASecurityProfileTemplate'; RowKey = $GUID; GUID = $GUID; JSON = (ConvertTo-Json -Depth 10 -Compress -InputObject $ProfileTemplate) }
        $Results.Add([pscustomobject]@{ state = 'success'; resultText = "Created security profile template '$($ProfileTemplate.name)'" })
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Saved security profile '$($ProfileTemplate.name)' as a template" -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Results.Add([pscustomobject]@{ state = 'error'; resultText = "Failed to save the security profile as a template: $(Get-NormalizedError -Message $_.Exception.Message)" })
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to save security profile $ID as a template: $($_.Exception.Message)" -Sev 'Error' -LogData (Get-CippException -Exception $_)
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{ StatusCode = $StatusCode; Body = @{ Results = @($Results) } })
}

function Invoke-AddGSASecurityProfileTemplate {
    <#
    .SYNOPSIS
        Creates or updates a Global Secure Access security profile template
    .DESCRIPTION
        Saves a security profile (priority, state and the filtering policy templates it links, each
        with its own priority) as a template. Conditional Access templates link security profile
        templates. Send GUID to update a template. Names and priorities are unique across templates,
        because two templates can land in the same tenant.
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.GlobalSecureAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    if (-not (Test-CippTemplateWriteAccess -PartitionKey 'GSASecurityProfileTemplate' -RowKey $Request.Body.GUID)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::Forbidden; Body = @{ Results = 'Roles limited to specific tenants cannot change or remove shared templates.' } })
    }

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    # The template to update; omit to create one
    $GUID = [string]$Request.Body.GUID
    # The profile name, also used as the template name
    $Name = ([string]$Request.Body.name).Trim()
    # Processing order in the tenant, 100-64999 (65000 is the baseline profile)
    $Priority = $Request.Body.priority -as [int]

    $Errors = [System.Collections.Generic.List[string]]::new()
    if (-not $Name) { $Errors.Add('name is required') }
    if ($null -eq $Priority -or $Priority -lt 100 -or $Priority -gt 64999) { $Errors.Add('priority must be a number from 100 to 64999') }
    switch ($Request.Body.state) {
        'enabled' {}
        'disabled' {}
        default { $Errors.Add("state must be enabled or disabled, not '$($Request.Body.state)'") }
    }
    # Each link: policy ({label, value} with the filtering policy template GUID, or the GUID), priority (100-65000), state and loggingState
    $Converted = ConvertTo-CIPPGSAProfileLink -Links $Request.Body.policies
    foreach ($ErrorText in $Converted.Errors) { $Errors.Add($ErrorText) }
    $Links = $Converted.Links
    if ($Errors.Count) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "Invalid security profile template: $($Errors -join '; ')" } })
    }

    try {
        $Table = Get-CippTable -tablename 'templates'
        $PolicyNames = @{}
        foreach ($Row in @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'GSAFilteringPolicyTemplate'")) { $PolicyNames[$Row.RowKey] = ($Row.JSON | ConvertFrom-Json).name }
        $Missing = @($Links.Where({ -not $PolicyNames.ContainsKey($_.policy.value) }).ForEach({ $_.policy.label ? "'$($_.policy.label)'" : $_.policy.value }))
        if ($Missing.Count) { throw [System.ArgumentException]::new("these filtering policy templates do not exist: $($Missing -join ', ')") }
        # The label is the name fallback a deploy uses when a GUID does not resolve, so keep it current.
        foreach ($Link in $Links) { $Link.policy.label = $PolicyNames[$Link.policy.value] }

        $Existing = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'GSASecurityProfileTemplate'")
        if ($GUID -and -not $Existing.Where({ $_.RowKey -eq $GUID })) {
            throw [System.Management.Automation.ItemNotFoundException]::new("Security profile template $GUID does not exist")
        }
        foreach ($Other in $Existing.Where({ $_.RowKey -ne $GUID })) {
            $OtherTemplate = $Other.JSON | ConvertFrom-Json
            if ($OtherTemplate.name -eq $Name) { throw [System.ArgumentException]::new("A security profile template named '$Name' already exists") }
            if ([int]$OtherTemplate.priority -eq $Priority) { throw [System.ArgumentException]::new("Priority $Priority is already used by security profile template '$($OtherTemplate.name)'") }
        }
        $Verb = if ($GUID) { 'Updated' } else { 'Created' }
        if (-not $GUID) { $GUID = (New-Guid).Guid }
        $JSON = ConvertTo-Json -Depth 10 -Compress -InputObject ([ordered]@{ name = $Name; description = [string]$Request.Body.description; priority = $Priority; state = [string]$Request.Body.state; policies = @($Links) })
        Add-CIPPAzDataTableEntity @Table -Force -Entity @{ PartitionKey = 'GSASecurityProfileTemplate'; RowKey = $GUID; GUID = $GUID; JSON = $JSON }
        $Result = "$Verb security profile template '$Name'"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = "Failed to save security profile template '$Name': $(Get-NormalizedError -Message $_.Exception.Message)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData (Get-CippException -Exception $_)
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{ StatusCode = $StatusCode; Body = @{ Results = $Result } })
}

function Invoke-AddGSAFilteringPolicyTemplate {
    <#
    .SYNOPSIS
        Creates or updates a Global Secure Access filtering policy template
    .DESCRIPTION
        Saves a web content filtering policy (block or allow, with web category, FQDN and URL rules)
        as a template that security profile templates link to. Send GUID to update a template.
        Policy names are unique in a tenant, so template names are unique too.
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.GlobalSecureAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    # The template to update; omit to create one
    $GUID = [string]$Request.Body.GUID
    # The policy name, also used as the template name
    $Name = ([string]$Request.Body.name).Trim()

    $Errors = [System.Collections.Generic.List[string]]::new()
    if (-not $Name) { $Errors.Add('name is required') }
    switch ($Request.Body.action) {
        'block' {}
        'allow' {}
        default { $Errors.Add("action must be block or allow, not '$($Request.Body.action)'") }
    }
    # Each rule: a name, a ruleType (webCategory, fqdn or url) and its destinations, as names/values or Graph destination objects
    $Converted = ConvertTo-CIPPGSAFilteringRule -Rules $Request.Body.policyRules
    foreach ($ErrorText in $Converted.Errors) { $Errors.Add($ErrorText) }
    $Rules = $Converted.Rules
    if ($Errors.Count) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "Invalid filtering policy template: $($Errors -join '; ')" } })
    }

    try {
        $Table = Get-CippTable -tablename 'templates'
        $Existing = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'GSAFilteringPolicyTemplate'")
        if ($GUID -and -not $Existing.Where({ $_.RowKey -eq $GUID })) {
            throw [System.Management.Automation.ItemNotFoundException]::new("Filtering policy template $GUID does not exist")
        }
        $Duplicate = $Existing.Where({ $_.RowKey -ne $GUID -and ($_.JSON | ConvertFrom-Json).name -eq $Name }, 'First')
        if ($Duplicate.Count) {
            throw [System.ArgumentException]::new("A filtering policy template named '$Name' already exists")
        }
        $Verb = if ($GUID) { 'Updated' } else { 'Created' }
        if (-not $GUID) { $GUID = (New-Guid).Guid }
        $JSON = ConvertTo-Json -Depth 10 -Compress -InputObject ([ordered]@{ name = $Name; description = [string]$Request.Body.description; action = [string]$Request.Body.action; policyRules = @($Rules) })
        Add-CIPPAzDataTableEntity @Table -Force -Entity @{ PartitionKey = 'GSAFilteringPolicyTemplate'; RowKey = $GUID; GUID = $GUID; JSON = $JSON }
        $Result = "$Verb filtering policy template '$Name'"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = "Failed to save filtering policy template '$Name': $(Get-NormalizedError -Message $_.Exception.Message)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData (Get-CippException -Exception $_)
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{ StatusCode = $StatusCode; Body = @{ Results = $Result } })
}

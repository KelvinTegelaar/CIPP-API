function Invoke-RemoveGSAFilteringPolicyTemplate {
    <#
    .SYNOPSIS
        Removes a Global Secure Access filtering policy template
    .DESCRIPTION
        Deletes a filtering policy template. Refused while a security profile template links it.
        Policies already deployed to tenants are left in place.
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.GlobalSecureAccess.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    # The GUID of the template to remove
    $ID = [string]($Request.Query.ID ?? $Request.Body.ID)
    if (-not $ID) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'ID is required' } })
    }

    try {
        $Table = Get-CippTable -tablename 'templates'
        $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'GSAFilteringPolicyTemplate' and RowKey eq '$(ConvertTo-CIPPODataFilterValue -Value $ID -Type String)'"
        if (-not $Row) { throw [System.Management.Automation.ItemNotFoundException]::new("Filtering policy template $ID does not exist") }
        $Name = ($Row.JSON | ConvertFrom-Json).name
        $LinkedBy = foreach ($ProfileRow in @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'GSASecurityProfileTemplate'")) {
            $ProfileTemplate = $ProfileRow.JSON | ConvertFrom-Json -Depth 20
            if (@($ProfileTemplate.policies).Where({ $_.policy.value -eq $ID }).Count) { $ProfileTemplate.name }
        }
        if ($LinkedBy) {
            throw [System.ArgumentException]::new("'$Name' is still linked by security profile templates: $(@($LinkedBy) -join ', ')")
        }
        Remove-CIPPAzDataTableEntity -Force @Table -Entity ($Row | Select-Object PartitionKey, RowKey)
        $Result = "Removed filtering policy template '$Name'"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = "Failed to remove filtering policy template $($ID): $(Get-NormalizedError -Message $_.Exception.Message)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData (Get-CippException -Exception $_)
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{ StatusCode = $StatusCode; Body = @{ Results = $Result } })
}

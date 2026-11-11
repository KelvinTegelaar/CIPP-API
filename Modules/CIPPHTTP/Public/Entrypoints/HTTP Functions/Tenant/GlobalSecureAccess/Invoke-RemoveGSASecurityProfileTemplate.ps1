function Invoke-RemoveGSASecurityProfileTemplate {
    <#
    .SYNOPSIS
        Removes a Global Secure Access security profile template
    .DESCRIPTION
        Deletes a security profile template. Refused while a Conditional Access template links it.
        Profiles already deployed to tenants are left in place.
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
        $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'GSASecurityProfileTemplate' and RowKey eq '$(ConvertTo-CIPPODataFilterValue -Value $ID -Type String)'"
        if (-not $Row) { throw [System.Management.Automation.ItemNotFoundException]::new("Security profile template $ID does not exist") }
        $Name = ($Row.JSON | ConvertFrom-Json).name
        $LinkedBy = foreach ($CARow in @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CATemplate'").Where({ "$($_.JSON)".Contains($ID) })) {
            $CATemplate = $CARow.JSON | ConvertFrom-Json -Depth 50
            if ($CATemplate.sessionControls.globalSecureAccessFilteringProfile.profileId.value -eq $ID) { $CATemplate.displayName }
        }
        if ($LinkedBy) {
            throw [System.ArgumentException]::new("'$Name' is still linked by Conditional Access templates: $(@($LinkedBy) -join ', ')")
        }
        Remove-CIPPAzDataTableEntity -Force @Table -Entity ($Row | Select-Object PartitionKey, RowKey)
        $Result = "Removed security profile template '$Name'"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Result = "Failed to remove security profile template $($ID): $(Get-NormalizedError -Message $_.Exception.Message)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData (Get-CippException -Exception $_)
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{ StatusCode = $StatusCode; Body = @{ Results = $Result } })
}

function Invoke-ListGSAFilteringPolicyTemplates {
    <#
    .SYNOPSIS
        Lists Global Secure Access filtering policy templates
    .DESCRIPTION
        Returns saved web content filtering policy templates (name, action and rules), or one
        template when GUID is given.
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.GlobalSecureAccess.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Return only this template
    $GUID = [string]$Request.Query.GUID
    try {
        $Table = Get-CippTable -tablename 'templates'
        $Filter = "PartitionKey eq 'GSAFilteringPolicyTemplate'"
        if ($GUID) { $Filter = "$Filter and RowKey eq '$(ConvertTo-CIPPODataFilterValue -Value $GUID -Type String)'" }
        $Templates = foreach ($Row in @(Get-CIPPAzDataTableEntity @Table -Filter $Filter)) {
            $Template = $Row.JSON | ConvertFrom-Json -Depth 20
            $Template.PSObject.Properties.Add([psnoteproperty]::new('GUID', $Row.RowKey))
            $Template
        }
        if ($GUID -and -not $Templates) {
            throw [System.Management.Automation.ItemNotFoundException]::new("Filtering policy template $GUID does not exist")
        }
        $Body = @($Templates)
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $Body = @{ Results = "Failed to list filtering policy templates: $(Get-NormalizedError -Message $_.Exception.Message)" }
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{ StatusCode = $StatusCode; Body = $Body })
}

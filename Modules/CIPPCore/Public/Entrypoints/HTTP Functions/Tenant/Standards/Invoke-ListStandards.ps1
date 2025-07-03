using namespace System.Net

function Invoke-ListStandards {
    <#
    .SYNOPSIS
    List security standards applied to Microsoft 365 tenants
    
    .DESCRIPTION
    Retrieves information about security standards and best practices applied to Microsoft 365 tenants
    
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.Read
        
    .NOTES
    Group: Standards
    Summary: List Standards
    Description: Retrieves information about security standards, best practices, and compliance configurations applied to Microsoft 365 tenants
    Tags: Standards,Security,Compliance
    Parameter: tenantFilter (string) [query] - The tenant to retrieve standards for (use 'AllTenants' for all tenants)
    Parameter: ShowConsolidated (boolean) [query] - Whether to show consolidated standards view
    Response: Returns an array of standards objects with the following properties:
    Response: - displayName (string): Tenant display name
    Response: - appliedBy (string): User or system that applied the standards
    Response: - appliedAt (string): Date and time when standards were applied
    Response: - standards (object): Detailed standards configuration object
    Response: - StandardsExport (string): Comma-separated list of applied standard names
    Response: When ShowConsolidated=true, returns consolidated standards data
    Example: [
      {
        "displayName": "contoso.onmicrosoft.com",
        "appliedBy": "admin@contoso.com",
        "appliedAt": "2024-01-15T10:30:00Z",
        "standards": {
          "MFA": {
            "enabled": true,
            "configuration": "enforced"
          },
          "PasswordPolicy": {
            "enabled": true,
            "minLength": 12
          }
        },
        "StandardsExport": "MFA, PasswordPolicy"
      }
    ]
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter


    if ($Request.Query.ShowConsolidated -eq $true) {
        $StandardQuery = @{
            TenantFilter = $TenantFilter
        }
        if ($TenantFilter -eq 'AllTenants') {
            $StandardQuery.ListAllTenants = $true
        }
        $CurrentStandards = @(Get-CIPPStandards @StandardQuery)
    }
    else {
        $Table = Get-CippTable -tablename 'standards'
        $Filter = "PartitionKey eq 'standards'"

        try {
            if ($TenantFilter) {
                $Tenants = (Get-CIPPAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json -Depth 15 -ErrorAction Stop | Where-Object Tenant -EQ $TenantFilter
            }
            else {
                $Tenants = (Get-CIPPAzDataTableEntity @Table -Filter $Filter).JSON | ConvertFrom-Json -Depth 15 -ErrorAction Stop
            }
        }
        catch {}

        $CurrentStandards = foreach ($tenant in $Tenants) {
            [PSCustomObject]@{
                displayName     = $tenant.tenant
                appliedBy       = $tenant.addedBy
                appliedAt       = $tenant.appliedAt
                standards       = $tenant.Standards
                StandardsExport = ($tenant.Standards.PSObject.Properties.Name) -join ', '
            }
        }

        $CurrentStandards = ConvertTo-Json -InputObject @($CurrentStandards) -Depth 15 -Compress
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $CurrentStandards
        })

}

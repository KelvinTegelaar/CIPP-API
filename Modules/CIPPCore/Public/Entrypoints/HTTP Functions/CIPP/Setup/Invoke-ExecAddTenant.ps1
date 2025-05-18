using namespace System.Net

Function Invoke-ExecAddTenant {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        # Get the tenant ID from the request body
        $tenantId = $Request.body.tenantId
        $displayName = $Request.body.displayName
        $defaultDomainName = $Request.body.defaultDomainName

        # Get the Tenants table
        $TenantsTable = Get-CippTable -tablename 'Tenants'

        # Check if tenant already exists
        $ExistingTenant = Get-CIPPAzDataTableEntity @TenantsTable -Filter "PartitionKey eq 'Tenants' and RowKey eq '$tenantId'"

        if ($ExistingTenant) {
            # Update existing tenant
            $ExistingTenant.delegatedPrivilegeStatus = 'directTenant'
            Add-CIPPAzDataTableEntity @TenantsTable -Entity $ExistingTenant -Force | Out-Null
            $Results = @{'message' = 'Successfully updated tenant.'; 'severity' = 'success' }
        } else {
            # Create new tenant entry
            try {
                # Get organization info
                $Organization = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/organization' -tenantid $tenantId -NoAuthCheck:$true -ErrorAction Stop

                if (-not $displayName) {
                    $displayName = $Organization[0].displayName
                }

                if (-not $defaultDomainName) {
                    # Try to get domains
                    try {
                        $Domains = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/domains?$top=999' -tenantid $tenantId -NoAuthCheck:$true -ErrorAction Stop
                        $defaultDomainName = ($Domains | Where-Object { $_.isDefault -eq $true }).id
                        $initialDomainName = ($Domains | Where-Object { $_.isInitial -eq $true }).id
                    } catch {
                        # If we can't get domains, use verified domains from organization
                        $defaultDomainName = ($Organization[0].verifiedDomains | Where-Object { $_.isDefault -eq $true }).name
                        $initialDomainName = ($Organization[0].verifiedDomains | Where-Object { $_.isInitial -eq $true }).name
                    }
                }
            } catch {
                Write-LogMessage -API 'Add-Tenant' -message "Failed to get information for tenant $tenantId - $($_.Exception.Message)" -Sev 'Critical'
                throw "Failed to get information for tenant $tenantId. Make sure the tenant is properly authenticated."
            }

            # Create new tenant object
            $NewTenant = [PSCustomObject]@{
                PartitionKey             = 'Tenants'
                RowKey                   = $tenantId
                customerId               = $tenantId
                displayName              = $displayName
                defaultDomainName        = $defaultDomainName
                initialDomainName        = $initialDomainName
                delegatedPrivilegeStatus = 'directTenant'
                domains                  = ''
                Excluded                 = $false
                ExcludeUser              = ''
                ExcludeDate              = ''
                GraphErrorCount          = 0
                LastGraphError           = ''
                RequiresRefresh          = $false
                LastRefresh              = (Get-Date).ToUniversalTime()
            }

            # Add tenant to table
            Add-CIPPAzDataTableEntity @TenantsTable -Entity $NewTenant -Force | Out-Null
            $Results = @{'message' = "Successfully added tenant $tenantId to the tenant list with directTenant status."; 'severity' = 'success' }
        }
    } catch {
        $Results = @{'message' = "Failed to add tenant: $($_.Exception.Message)"; 'state' = 'error'; 'severity' = 'error' }
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })
}

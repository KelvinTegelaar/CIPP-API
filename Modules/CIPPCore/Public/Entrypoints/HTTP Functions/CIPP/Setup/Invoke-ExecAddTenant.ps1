function Invoke-ExecAddTenant {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        # Get the tenant ID from the request body
        $tenantId = $Request.body.tenantId
        $defaultDomainName = $Request.body.defaultDomainName

        # Get the Tenants table
        $TenantsTable = Get-CippTable -tablename 'Tenants'
        #force a refresh of the authentication info
        $auth = Get-CIPPAuthentication
        # Check if tenant already exists
        $ExistingTenant = Get-CIPPAzDataTableEntity @TenantsTable -Filter "PartitionKey eq 'Tenants' and RowKey eq '$tenantId'"

        if ($tenantId -eq $env:TenantID) {
            # If the tenant is the partner tenant, return an error because you cannot add the partner tenant as direct tenant
            $Results = @{'message' = 'You cannot add the partner tenant as a direct tenant. Please connect the tenant using the "Connect to Partner Tenant" option. '; 'severity' = 'error'; }
        } elseif ($ExistingTenant) {
            # Update existing tenant
            $ExistingTenant.delegatedPrivilegeStatus = 'directTenant'
            Add-CIPPAzDataTableEntity @TenantsTable -Entity $ExistingTenant -Force | Out-Null
            $Results = @{'message' = 'Successfully updated tenant.'; 'severity' = 'success' }
        } else {
            # Create new tenant entry
            try {
                # Get tenant information from Microsoft Graph using bulk request
                $headers = @{ Authorization = "Bearer $($request.body.accessToken)" }

                $BulkRequests = @(
                    @{
                        id     = 'organization'
                        method = 'GET'
                        url    = '/organization?$select=id,displayName'
                    }
                    @{
                        id     = 'domains'
                        method = 'GET'
                        url    = '/domains?$top=999'
                    }
                )

                $BulkBody = @{
                    requests = $BulkRequests
                } | ConvertTo-Json -Depth 10

                $BulkResponse = Invoke-RestMethod -Uri 'https://graph.microsoft.com/v1.0/$batch' -Headers $headers -Method POST -Body $BulkBody -ContentType 'application/json' -ErrorAction Stop

                # Parse bulk response
                $OrgResponse = ($BulkResponse.responses | Where-Object { $_.id -eq 'organization' }).body.value
                $DomainsResponse = ($BulkResponse.responses | Where-Object { $_.id -eq 'domains' }).body.value

                $displayName = $OrgResponse.displayName
                $defaultDomainName = ($DomainsResponse | Where-Object { $_.isDefault -eq $true }).id
                $initialDomainName = ($DomainsResponse | Where-Object { $_.isInitial -eq $true }).id
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
            $Results = @{'message' = "Successfully added tenant $displayName ($defaultDomainName) to the tenant list with Direct Tenant status. Permission refresh queued, the tenant will be available shortly."; 'severity' = 'success' }
            Write-LogMessage -tenant $defaultDomainName -tenantid $tenantId -API 'NewTenant' -message "Added tenant $displayName ($defaultDomainName) with Direct Tenant status." -Sev 'Info'

            # Trigger CPV refresh to push remaining permissions to this specific tenant
            try {
                $Queue = New-CippQueueEntry -Name "Update Permissions - $displayName" -TotalTasks 1
                $TenantBatch = @([PSCustomObject]@{
                        defaultDomainName = $defaultDomainName
                        customerId        = $tenantId
                        displayName       = $displayName
                        FunctionName      = 'UpdatePermissionsQueue'
                        QueueId           = $Queue.RowKey
                    })
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'UpdatePermissionsOrchestrator'
                    Batch            = @($TenantBatch)
                }
                Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
                Write-Information "Started permissions update orchestrator for $displayName"
            } catch {
                Write-Warning "Failed to start permissions orchestrator: $($_.Exception.Message)"
            }

        }
    } catch {
        $Results = @{'message' = "Failed to add tenant: $($_.Exception.Message)"; 'state' = 'error'; 'severity' = 'error' }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Results
        })
}

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
        # AnyTenant: onboarding writes tenant credentials; require unrestricted tenant scope
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        if ($AllowedTenants -notcontains 'AllTenants') {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body       = @{'message' = 'Adding a tenant requires unrestricted tenant access'; 'severity' = 'error' }
                })
        }

        # Get the tenant ID from the request body
        $tenantId = $Request.body.tenantId
        $defaultDomainName = $Request.body.defaultDomainName

        # The account that consented is recorded so the connection can be traced and refreshed
        # later. The auth date is stamped server side rather than trusting the client.
        $ServiceAccount = $Request.body.username ?? ''
        $AuthDate = (Get-Date).ToUniversalTime()

        # Get the Tenants table
        $TenantsTable = Get-CippTable -tablename 'Tenants'
        #force a refresh of the authentication info
        $auth = Get-CIPPAuthentication
        # Check if tenant already exists
        $ExistingTenant = Get-CIPPAzDataTableEntity @TenantsTable -Filter "PartitionKey eq 'Tenants' and RowKey eq '$tenantId'"

        if ($tenantId -eq $env:TenantID) {
            # If the tenant is the partner tenant, return an error because you cannot add the partner tenant as direct tenant
            $Results = @{'message' = 'You cannot add the partner tenant as a direct tenant. Please connect the tenant using the "Connect to Partner Tenant" option. '; 'severity' = 'error'; }
        } elseif ($ExistingTenant -and $ExistingTenant.delegatedPrivilegeStatus -ne 'directTenant') {
            # Converting an existing GDAP tenant in place would silently change how CIPP
            # authenticates to it. Require the tenant to be offboarded first so the switch is
            # deliberate.
            # The sign-in that got us here already stored a per-tenant refresh token, so discard it
            # again - keeping it would leave a credential behind for a conversion we just refused.
            Remove-CIPPDirectTenantToken -TenantId $tenantId

            $Results = @{'message' = "$($ExistingTenant.displayName) is already onboarded as a GDAP tenant and cannot be converted to a Direct Tenant. To manage it as a Direct Tenant, remove the tenant first under Settings > Tenants, then add it again using the Direct Tenant flow."; 'severity' = 'error' }
            Write-LogMessage -tenant $ExistingTenant.defaultDomainName -tenantid $ExistingTenant.customerId -API 'NewTenant' -message "Blocked conversion of GDAP tenant $($ExistingTenant.displayName) to a Direct Tenant, attempted by $ServiceAccount." -Sev 'Warn'
        } elseif ($ExistingTenant) {
            # Existing direct tenant - refresh the stored credentials and service account details.
            $ExistingTenant | Add-Member -NotePropertyName 'directTenantUserPrincipalName' -NotePropertyValue $ServiceAccount -Force
            $ExistingTenant | Add-Member -NotePropertyName 'directTenantAuthDate' -NotePropertyValue $AuthDate -Force
            Add-CIPPAzDataTableEntity @TenantsTable -Entity $ExistingTenant -Force | Out-Null

            $Results = @{'message' = "Successfully updated the credentials for $($ExistingTenant.displayName)."; 'severity' = 'success' }
            Write-LogMessage -tenant $ExistingTenant.defaultDomainName -tenantid $ExistingTenant.customerId -API 'NewTenant' -message "Refreshed Direct Tenant credentials for $($ExistingTenant.displayName) using $ServiceAccount." -Sev 'Info'
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
                PartitionKey                  = 'Tenants'
                RowKey                        = $tenantId
                customerId                    = $tenantId
                displayName                   = $displayName
                defaultDomainName             = $defaultDomainName
                initialDomainName             = $initialDomainName
                delegatedPrivilegeStatus      = 'directTenant'
                directTenantUserPrincipalName = $ServiceAccount
                directTenantAuthDate          = $AuthDate
                domains                       = ''
                Excluded                      = $false
                ExcludeUser                   = ''
                ExcludeDate                   = ''
                GraphErrorCount               = 0
                LastGraphError                = ''
                RequiresRefresh               = $false
                LastRefresh                   = (Get-Date).ToUniversalTime()
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
                Start-CIPPOrchestrator -InputObject $InputObject
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

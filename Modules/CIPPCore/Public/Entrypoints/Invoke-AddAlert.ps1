using namespace System.Net

Function Invoke-AddAlert {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $Tenants = $Request.body.tenantFilter
    $Table = get-cipptable -TableName 'SchedulerConfig'

    $Results = foreach ($Tenant in $tenants) {
        try {
            Write-Host "Working on $Tenant"
            if ($tenant -ne 'AllTenants') {
                $TenantID = (get-tenants | Where-Object -Property defaultDomainName -EQ $Tenant).customerId
            } else {
                $TenantID = 'AllTenants'
            }
            if ($Request.body.SetAlerts) {
                $CompleteObject = @{
                    tenant            = $tenant
                    tenantid          = $TenantID
                    AdminPassword     = [bool]$Request.body.AdminPassword
                    DefenderMalware   = [bool]$Request.body.DefenderMalware
                    DefenderStatus    = [bool]$Request.body.DefenderStatus
                    MFAAdmins         = [bool]$Request.body.MFAAdmins
                    MFAAlertUsers     = [bool]$Request.body.MFAAlertUsers
                    NewGA             = [bool]$Request.body.NewGA
                    NewRole           = [bool]$Request.body.NewRole
                    QuotaUsed         = [bool]$Request.body.QuotaUsed
                    UnusedLicenses    = [bool]$Request.body.UnusedLicenses
                    OverusedLicenses  = [bool]$Request.body.OverusedLicenses
                    AppSecretExpiry   = [bool]$Request.body.AppSecretExpiry
                    ApnCertExpiry     = [bool]$Request.body.ApnCertExpiry
                    VppTokenExpiry    = [bool]$Request.body.VppTokenExpiry
                    DepTokenExpiry    = [bool]$Request.body.DepTokenExpiry
                    NoCAConfig        = [bool]$Request.body.NoCAConfig
                    SecDefaultsUpsell = [bool]$Request.body.SecDefaultsUpsell
                    SharePointQuota   = [bool]$Request.body.SharePointQuota
                    ExpiringLicenses  = [bool]$Request.body.ExpiringLicenses
                    type              = 'Alert'
                    RowKey            = $TenantID
                    PartitionKey      = 'Alert'
                }
                $Table = get-cipptable -TableName 'SchedulerConfig'
                Add-CIPPAzDataTableEntity @Table -Entity $CompleteObject -Force
            } else {
                $URL = ($request.headers.'x-ms-original-url').split('/api') | Select-Object -First 1
                if ($Tenant -eq 'AllTenants') {
                    Get-Tenants | ForEach-Object {
                        $params = @{
                            TenantFilter  = $_.defaultDomainName
                            auditLogAPI   = $true
                            operations    = $Request.body.ifs.selection
                            BaseURL       = $URL
                            ExecutingUser = $Request.headers.'x-ms-client-principal'
                        }
                        Push-OutputBinding -Name Subscription -Value $Params
                    }
                    $CompleteObject = @{
                        tenant       = 'AllTenants'
                        type         = 'webhookcreation'
                        RowKey       = 'AllTenantsWebhookCreation'
                        PartitionKey = 'webhookcreation'
                    }
                    Add-CIPPAzDataTableEntity @Table -Entity $CompleteObject -Force
                } else {
                    $params = @{
                        TenantFilter  = $tenant
                        auditLogAPI   = $true
                        operations    = $Request.body.ifs.selection
                        BaseURL       = $URL
                        ExecutingUser = $Request.headers.'x-ms-client-principal'
                    }
                    New-CIPPGraphSubscription @params
                }
                $CompleteObject = @{
                    Tenant       = [string]$tenant
                    if           = [string](ConvertTo-Json -Depth 10 -Compress -InputObject $Request.body.ifs)
                    execution    = [string](ConvertTo-Json -Depth 10 -Compress -InputObject $Request.body.do)
                    type         = 'WebhookAlert'
                    RowKey       = [string](New-Guid)
                    PartitionKey = 'WebhookAlert'
                }
                Add-CIPPAzDataTableEntity @Table -Entity $CompleteObject -Force

            }
            "Successfully added Alert for $($Tenant) to queue."
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message "Successfully added Alert for $($Tenant) to queue." -Sev 'Info'
        } catch {
            Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $tenant -message "Failed to add Alert for for $($Tenant) to queue" -Sev 'Error'
            "Failed to add Alert for for $($Tenant) to queue $($_.Exception.message)"
        }
    }

    $body = [pscustomobject]@{'Results' = @($results) }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}

function New-CIPPBackupTask {
    [CmdletBinding()]
    param (
        $Task,
        $TenantFilter
    )

    $FunctionStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host "CIPPBACKUP: Starting backup task: $Task for tenant: $TenantFilter"

    $BackupData = switch ($Task) {
        'CippCustomVariables' {
            $TaskStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Write-Host "CIPPBACKUP: Backing up Custom Variables for $TenantFilter"
            $ReplaceTable = Get-CIPPTable -tablename 'CippReplacemap'

            # Get tenant-specific variables
            $Tenant = Get-Tenants -TenantFilter $TenantFilter
            $CustomerId = $Tenant.customerId

            $TenantVariables = Get-CIPPAzDataTableEntity @ReplaceTable -Filter "PartitionKey eq '$CustomerId'"

            # If backing up AllTenants, also get global variables
            if ($TenantFilter -eq 'AllTenants') {
                $GlobalVariables = Get-CIPPAzDataTableEntity @ReplaceTable -Filter "PartitionKey eq 'AllTenants'"
                $AllVariables = @($TenantVariables) + @($GlobalVariables)
                $TaskStopwatch.Stop()
                Write-Host "CIPPBACKUP: CippCustomVariables backup completed in $($TaskStopwatch.Elapsed.TotalSeconds) seconds"
                $AllVariables
            } else {
                $TaskStopwatch.Stop()
                Write-Host "CIPPBACKUP: CippCustomVariables backup completed in $($TaskStopwatch.Elapsed.TotalSeconds) seconds"
                $TenantVariables
            }
        }
        'users' {
            $TaskStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Write-Host "CIPPBACKUP: Backup users for $TenantFilter"
            $Users = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/users?$top=999' -tenantid $TenantFilter | Select-Object * -ExcludeProperty mail, provisionedPlans, onPrem*, *passwordProfile*, *serviceProvisioningErrors*, isLicenseReconciliationNeeded, isManagementRestricted, isResourceAccount, *date*, *external*, identities, deletedDateTime, isSipEnabled, assignedPlans, cloudRealtimeCommunicationInfo, deviceKeys, provisionedPlan, securityIdentifier
            #remove the property if the value is $null
            $users = $Users | ForEach-Object {
                $_.psobject.properties | Where-Object { $null -eq $_.Value } | ForEach-Object {
                    $_.psobject.properties.Remove($_.Name)
                }
            }
            $TaskStopwatch.Stop()
            Write-Host "CIPPBACKUP: Users backup completed in $($TaskStopwatch.Elapsed.TotalSeconds) seconds"
            $Users

        }
        'groups' {
            $TaskStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Write-Host "CIPPBACKUP: Backup groups for $TenantFilter"
            $Groups = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$top=999' -tenantid $TenantFilter
            $TaskStopwatch.Stop()
            Write-Host "CIPPBACKUP: Groups backup completed in $($TaskStopwatch.Elapsed.TotalSeconds) seconds"
            $Groups
        }
        'ca' {
            $TaskStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Write-Host "CIPPBACKUP: Backup Conditional Access Policies for $TenantFilter"
            $Policies = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/conditionalAccess/policies?$top=999' -tenantid $TenantFilter -AsApp $true
            Write-Host 'CIPPBACKUP: Creating templates for found Conditional Access Policies'
            foreach ($policy in $policies) {
                try {
                    New-CIPPCATemplate -TenantFilter $TenantFilter -JSON $policy
                } catch {
                    "Failed to create a template of the Conditional Access Policy with ID: $($policy.id). Error: $($_.Exception.Message)"
                }
            }
            $TaskStopwatch.Stop()
            Write-Host "CIPPBACKUP: Conditional Access backup completed in $($TaskStopwatch.Elapsed.TotalSeconds) seconds"
        }
        'intuneconfig' {
            $TaskStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Write-Host "CIPPBACKUP: Backup Intune Configuration Policies for $TenantFilter"
            $GraphURLS = @("https://graph.microsoft.com/beta/deviceManagement/deviceConfigurations?`$select=id,displayName,lastModifiedDateTime,roleScopeTagIds,microsoft.graph.unsupportedDeviceConfiguration/originalEntityTypeName&`$expand=assignments&top=1000"
                'https://graph.microsoft.com/beta/deviceManagement/windowsDriverUpdateProfiles'
                "https://graph.microsoft.com/beta/deviceManagement/groupPolicyConfigurations?`$expand=assignments&top=999"
                "https://graph.microsoft.com/beta/deviceAppManagement/mobileAppConfigurations?`$expand=assignments&`$filter=microsoft.graph.androidManagedStoreAppConfiguration/appSupportsOemConfig%20eq%20true"
                'https://graph.microsoft.com/beta/deviceManagement/configurationPolicies'
                'https://graph.microsoft.com/beta/deviceManagement/windowsFeatureUpdateProfiles'
                'https://graph.microsoft.com/beta/deviceManagement/windowsQualityUpdatePolicies'
                'https://graph.microsoft.com/beta/deviceManagement/windowsQualityUpdateProfiles'
            )

            foreach ($url in $GraphURLS) {
                try {
                    $Policies = New-GraphGetRequest -uri "$($url)" -tenantid $TenantFilter
                    $URLName = (($url).split('?') | Select-Object -First 1) -replace 'https://graph.microsoft.com/beta/deviceManagement/', ''
                    foreach ($Policy in $Policies) {
                        try {
                            New-CIPPIntuneTemplate -TenantFilter $TenantFilter -URLName $URLName -ID $Policy.ID
                        } catch {
                            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                            "Failed to create a template of the Intune Configuration Policy with ID: $($Policy.id). Error: $ErrorMessage"
                        }
                    }
                } catch {
                    Write-Host "CIPPBACKUP: Failed to backup $url"
                }
            }
            $TaskStopwatch.Stop()
            Write-Host "CIPPBACKUP: Intune Configuration backup completed in $($TaskStopwatch.Elapsed.TotalSeconds) seconds"
        }
        'intunecompliance' {
            $TaskStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Write-Host "CIPPBACKUP: Backup Intune Configuration Policies for $TenantFilter"

            New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies?$top=999' -tenantid $TenantFilter | ForEach-Object {
                New-CIPPIntuneTemplate -TenantFilter $TenantFilter -URLName 'deviceCompliancePolicies' -ID $_.ID
            }
            $TaskStopwatch.Stop()
            Write-Host "CIPPBACKUP: Intune Compliance backup completed in $($TaskStopwatch.Elapsed.TotalSeconds) seconds"
        }

        'intuneprotection' {
            $TaskStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Write-Host "CIPPBACKUP: Backup Intune Configuration Policies for $TenantFilter"

            New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceAppManagement/managedAppPolicies?$top=999' -tenantid $TenantFilter | ForEach-Object {
                New-CIPPIntuneTemplate -TenantFilter $TenantFilter -URLName 'managedAppPolicies' -ID $_.ID
            }
            $TaskStopwatch.Stop()
            Write-Host "CIPPBACKUP: Intune Protection backup completed in $($TaskStopwatch.Elapsed.TotalSeconds) seconds"
        }

        'antispam' {
            $TaskStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Write-Host "CIPPBACKUP: Backup Anti-Spam Policies for $TenantFilter"

            $Policies = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-HostedContentFilterPolicy' | Select-Object * -ExcludeProperty *odata*, *data.type*
            $Rules = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-HostedContentFilterRule' | Select-Object * -ExcludeProperty *odata*, *data.type*

            $Policies | ForEach-Object {
                $_.psobject.properties | Where-Object { $null -eq $_.Value } | ForEach-Object {
                    $_.psobject.properties.Remove($_.Name)
                }
            }

            $Rules | ForEach-Object {
                $_.psobject.properties | Where-Object { $null -eq $_.Value } | ForEach-Object {
                    $_.psobject.properties.Remove($_.Name)
                }
            }

            $JSON = @{ policies = $Policies; rules = $Rules } | ConvertTo-Json -Depth 10
            $TaskStopwatch.Stop()
            Write-Host "CIPPBACKUP: Anti-Spam backup completed in $($TaskStopwatch.Elapsed.TotalSeconds) seconds"
            $JSON
        }

        'antiphishing' {
            $TaskStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Write-Host "CIPPBACKUP: Backup Anti-Phishing Policies for $TenantFilter"

            $Policies = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-AntiPhishPolicy' | Select-Object * -ExcludeProperty *odata*, *data.type*
            $Rules = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-AntiPhishRule' | Select-Object * -ExcludeProperty *odata*, *data.type*

            $Policies | ForEach-Object {
                $_.psobject.properties | Where-Object { $null -eq $_.Value } | ForEach-Object {
                    $_.psobject.properties.Remove($_.Name)
                }
            }

            $Rules | ForEach-Object {
                $_.psobject.properties | Where-Object { $null -eq $_.Value } | ForEach-Object {
                    $_.psobject.properties.Remove($_.Name)
                }
            }

            $JSON = @{ policies = $Policies; rules = $Rules } | ConvertTo-Json -Depth 10
            $TaskStopwatch.Stop()
            Write-Host "CIPPBACKUP: Anti-Phishing backup completed in $($TaskStopwatch.Elapsed.TotalSeconds) seconds"
            $JSON
        }

        'CippWebhookAlerts' {
            $TaskStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Write-Host "CIPPBACKUP: Backup Webhook Alerts for $TenantFilter"
            $WebhookTable = Get-CIPPTable -TableName 'WebhookRules'
            $WebhookData = Get-CIPPAzDataTableEntity @WebhookTable | Where-Object { $TenantFilter -in ($_.Tenants | ConvertFrom-Json).value }
            $TaskStopwatch.Stop()
            Write-Host "CIPPBACKUP: Webhook Alerts backup completed in $($TaskStopwatch.Elapsed.TotalSeconds) seconds"
            $WebhookData
        }
        'CippScriptedAlerts' {
            $TaskStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            Write-Host "CIPPBACKUP: Backup Scripted Alerts for $TenantFilter"
            $ScheduledTasks = Get-CIPPTable -TableName 'ScheduledTasks'
            $ScriptedAlerts = Get-CIPPAzDataTableEntity @ScheduledTasks | Where-Object { $_.hidden -eq $true -and $_.command -like 'Get-CippAlert*' -and $TenantFilter -in $_.Tenant }
            $TaskStopwatch.Stop()
            Write-Host "CIPPBACKUP: Scripted Alerts backup completed in $($TaskStopwatch.Elapsed.TotalSeconds) seconds"
            $ScriptedAlerts
        }
    }

    $FunctionStopwatch.Stop()
    Write-Host "CIPPBACKUP: Total backup task completed in $($FunctionStopwatch.Elapsed.TotalSeconds) seconds"
    return $BackupData
}


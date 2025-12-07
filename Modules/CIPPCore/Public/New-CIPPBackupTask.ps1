function New-CIPPBackupTask {
    [CmdletBinding()]
    param (
        $Task,
        $TenantFilter
    )

    $BackupData = switch ($Task) {
        'CippCustomVariables' {
            Measure-CIPPTask -Name 'CIPP.BackupCompleted' -Section 'CustomVariables' -Execute {
                $ReplaceTable = Get-CIPPTable -tablename 'CippReplacemap'

                # Get tenant-specific variables
                $Tenant = Get-Tenants -TenantFilter $TenantFilter
                $CustomerId = $Tenant.customerId
                $TenantVariables = Get-CIPPAzDataTableEntity @ReplaceTable -Filter "PartitionKey eq '$CustomerId'"

                # If backing up AllTenants, also get global variables
                if ($TenantFilter -eq 'AllTenants') {
                    $GlobalVariables = Get-CIPPAzDataTableEntity @ReplaceTable -Filter "PartitionKey eq 'AllTenants'"
                    $AllVariables = @($TenantVariables) + @($GlobalVariables)
                    $AllVariables
                } else {
                    $TenantVariables
                }
            }
        }
        'users' {
            Measure-CIPPTask -Name 'CIPP.BackupCompleted' -Section 'Users' -Execute {
                $Users = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/users?$top=999' -tenantid $TenantFilter | Select-Object * -ExcludeProperty mail, provisionedPlans, onPrem*, *passwordProfile*, *serviceProvisioningErrors*, isLicenseReconciliationNeeded, isManagementRestricted, isResourceAccount, *date*, *external*, identities, deletedDateTime, isSipEnabled, assignedPlans, cloudRealtimeCommunicationInfo, deviceKeys, provisionedPlan, securityIdentifier
                #remove the property if the value is $null
                $users = $Users | ForEach-Object {
                    $_.psobject.properties | Where-Object { $null -eq $_.Value } | ForEach-Object {
                        $_.psobject.properties.Remove($_.Name)
                    }
                }
                $Users
            }
        }
        'groups' {
            Measure-CIPPTask -Name 'CIPP.BackupCompleted' -Section 'Groups' -Execute {
                New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$top=999' -tenantid $TenantFilter
            }
        }
        'ca' {
            Measure-CIPPTask -Name 'CIPP.BackupCompleted' -Section 'ConditionalAccess' -Execute {
                $Policies = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/conditionalAccess/policies?$top=999' -tenantid $TenantFilter -AsApp $true
                foreach ($policy in $policies) {
                    try {
                        New-CIPPCATemplate -TenantFilter $TenantFilter -JSON $policy
                    } catch {
                        "Failed to create a template of the Conditional Access Policy with ID: $($policy.id). Error: $($_.Exception.Message)"
                    }
                }
            }
        }
        'intuneconfig' {
            Measure-CIPPTask -Name 'CIPP.BackupCompleted' -Section 'IntuneConfiguration' -Execute {
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
                        Write-Host "Failed to backup $url"
                    }
                }
            }
        }
        'intunecompliance' {
            Measure-CIPPTask -Name 'CIPP.BackupCompleted' -Section 'IntuneCompliance' -Execute {
                New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies?$top=999' -tenantid $TenantFilter | ForEach-Object {
                    New-CIPPIntuneTemplate -TenantFilter $TenantFilter -URLName 'deviceCompliancePolicies' -ID $_.ID
                }
            }
        }

        'intuneprotection' {
            Measure-CIPPTask -Name 'CIPP.BackupCompleted' -Section 'IntuneProtection' -Execute {
                New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/deviceAppManagement/managedAppPolicies?$top=999' -tenantid $TenantFilter | ForEach-Object {
                    New-CIPPIntuneTemplate -TenantFilter $TenantFilter -URLName 'managedAppPolicies' -ID $_.ID
                }
            }
        }

        'antispam' {
            Measure-CIPPTask -Name 'CIPP.BackupCompleted' -Section 'AntiSpam' -Execute {
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

                @{ policies = $Policies; rules = $Rules } | ConvertTo-Json -Depth 10
            }
        }

        'antiphishing' {
            Measure-CIPPTask -Name 'CIPP.BackupCompleted' -Section 'AntiPhishing' -Execute {
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

                @{ policies = $Policies; rules = $Rules } | ConvertTo-Json -Depth 10
            }
        }

        'CippWebhookAlerts' {
            Measure-CIPPTask -Name 'CIPP.BackupCompleted' -Section 'WebhookAlerts' -Execute {
                $WebhookTable = Get-CIPPTable -TableName 'WebhookRules'
                Get-CIPPAzDataTableEntity @WebhookTable | Where-Object { $TenantFilter -in ($_.Tenants | ConvertFrom-Json).value }
            }
        }
        'CippScriptedAlerts' {
            Measure-CIPPTask -Name 'CIPP.BackupCompleted' -Section 'ScriptedAlerts' -Execute {
                $ScheduledTasks = Get-CIPPTable -TableName 'ScheduledTasks'
                Get-CIPPAzDataTableEntity @ScheduledTasks | Where-Object { $_.hidden -eq $true -and $_.command -like 'Get-CippAlert*' -and $TenantFilter -in $_.Tenant }
            }
        }
    }

    return $BackupData
}


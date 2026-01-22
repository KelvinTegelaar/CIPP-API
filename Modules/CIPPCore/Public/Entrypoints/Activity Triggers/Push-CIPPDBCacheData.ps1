function Push-CIPPDBCacheData {
    <#
    .SYNOPSIS
        Orchestrator function to collect and cache all data for a single tenant

    .DESCRIPTION
        Builds a dynamic batch of cache collection tasks based on tenant license capabilities

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)
    Write-Host "Starting cache collection orchestration for tenant: $($Item.TenantFilter) - Queue: $($Item.QueueName) (ID: $($Item.QueueId))"
    $TenantFilter = $Item.TenantFilter
    $QueueId = $Item.QueueId

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Starting database cache orchestration for tenant' -sev Info

        # Check tenant capabilities for license-specific features
        $IntuneCapable = Test-CIPPStandardLicense -StandardName 'IntuneLicenseCheck' -TenantFilter $TenantFilter -RequiredCapabilities @('INTUNE_A', 'MDM_Services', 'EMS', 'SCCM', 'MICROSOFTINTUNEPLAN1') -SkipLog
        $ConditionalAccessCapable = Test-CIPPStandardLicense -StandardName 'ConditionalAccessLicenseCheck' -TenantFilter $TenantFilter -RequiredCapabilities @('AAD_PREMIUM', 'AAD_PREMIUM_P2') -SkipLog
        $AzureADPremiumP2Capable = Test-CIPPStandardLicense -StandardName 'AzureADPremiumP2LicenseCheck' -TenantFilter $TenantFilter -RequiredCapabilities @('AAD_PREMIUM_P2') -SkipLog
        $ExchangeCapable = Test-CIPPStandardLicense -StandardName 'ExchangeLicenseCheck' -TenantFilter $TenantFilter -RequiredCapabilities @('EXCHANGE_S_STANDARD', 'EXCHANGE_S_ENTERPRISE', 'EXCHANGE_S_STANDARD_GOV', 'EXCHANGE_S_ENTERPRISE_GOV', 'EXCHANGE_LITE') -SkipLog

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "License capabilities - Intune: $IntuneCapable, Conditional Access: $ConditionalAccessCapable, Azure AD Premium P2: $AzureADPremiumP2Capable, Exchange: $ExchangeCapable" -sev Info

        # Build dynamic batch of cache collection tasks based on license capabilities
        $Batch = [System.Collections.Generic.List[object]]::new()

        #region All Licenses - Basic tenant data collection
        $BasicCacheFunctions = @(
            'Users'
            'Groups'
            'Guests'
            'ServicePrincipals'
            'Apps'
            'Devices'
            'Organization'
            'Roles'
            'AdminConsentRequestPolicy'
            'AuthorizationPolicy'
            'AuthenticationMethodsPolicy'
            'DeviceSettings'
            'DirectoryRecommendations'
            'CrossTenantAccessPolicy'
            'DefaultAppManagementPolicy'
            'Settings'
            'SecureScore'
            'PIMSettings'
            'Domains'
            'RoleEligibilitySchedules'
            'RoleManagementPolicies'
            'RoleAssignmentScheduleInstances'
            'B2BManagementPolicy'
            'AuthenticationFlowsPolicy'
            'DeviceRegistrationPolicy'
            'CredentialUserRegistrationDetails'
            'UserRegistrationDetails'
            'OAuth2PermissionGrants'
            'AppRoleAssignments'
            'LicenseOverview'
            'MFAState'
        )

        foreach ($CacheFunction in $BasicCacheFunctions) {
            $Batch.Add(@{
                    FunctionName = 'ExecCIPPDBCache'
                    Name         = $CacheFunction
                    TenantFilter = $TenantFilter
                    QueueId      = $QueueId
                })
        }
        #endregion All Licenses

        #region Exchange Licensed - Exchange Online features
        if ($ExchangeCapable) {
            $ExchangeCacheFunctions = @(
                'ExoAntiPhishPolicies'
                'ExoMalwareFilterPolicies'
                'ExoSafeLinksPolicies'
                'ExoSafeAttachmentPolicies'
                'ExoTransportRules'
                'ExoDkimSigningConfig'
                'ExoOrganizationConfig'
                'ExoAcceptedDomains'
                'ExoHostedContentFilterPolicy'
                'ExoHostedOutboundSpamFilterPolicy'
                'ExoAntiPhishPolicy'
                'ExoSafeLinksPolicy'
                'ExoSafeAttachmentPolicy'
                'ExoMalwareFilterPolicy'
                'ExoAtpPolicyForO365'
                'ExoQuarantinePolicy'
                'ExoRemoteDomain'
                'ExoSharingPolicy'
                'ExoAdminAuditLogConfig'
                'ExoPresetSecurityPolicy'
                'ExoTenantAllowBlockList'
                'Mailboxes'
                'CASMailboxes'
                'MailboxUsage'
                'OneDriveUsage'
            )

            foreach ($CacheFunction in $ExchangeCacheFunctions) {
                $Batch.Add(@{
                        FunctionName = 'ExecCIPPDBCache'
                        Name         = $CacheFunction
                        TenantFilter = $TenantFilter
                        QueueId      = $QueueId
                    })
            }
        } else {
            Write-Host 'Skipping Exchange Online data collection - tenant does not have required license'
        }
        #endregion Exchange Licensed

        #region Conditional Access Licensed - Azure AD Premium features
        if ($ConditionalAccessCapable) {
            $Batch.Add(@{
                    FunctionName = 'ExecCIPPDBCache'
                    Name         = 'ConditionalAccessPolicies'
                    TenantFilter = $TenantFilter
                    QueueId      = $QueueId
                })
        } else {
            Write-Host 'Skipping Conditional Access data collection - tenant does not have required license'
        }
        #endregion Conditional Access Licensed

        #region Azure AD Premium P2 - Identity Protection features
        if ($AzureADPremiumP2Capable) {
            $P2CacheFunctions = @(
                'RiskyUsers'
                'RiskyServicePrincipals'
                'ServicePrincipalRiskDetections'
                'RiskDetections'
            )
            foreach ($CacheFunction in $P2CacheFunctions) {
                $Batch.Add(@{
                        FunctionName = 'ExecCIPPDBCache'
                        Name         = $CacheFunction
                        TenantFilter = $TenantFilter
                        QueueId      = $QueueId
                    })
            }
        } else {
            Write-Host 'Skipping Azure AD Premium P2 Identity Protection data collection - tenant does not have required license'
        }
        #endregion Azure AD Premium P2

        #region Intune Licensed - Intune management features
        if ($IntuneCapable) {
            $IntuneCacheFunctions = @(
                'ManagedDevices'
                'IntunePolicies'
                'ManagedDeviceEncryptionStates'
                'IntuneAppProtectionPolicies'
            )
            foreach ($CacheFunction in $IntuneCacheFunctions) {
                $Batch.Add(@{
                        FunctionName = 'ExecCIPPDBCache'
                        Name         = $CacheFunction
                        TenantFilter = $TenantFilter
                        QueueId      = $QueueId
                    })
            }
        } else {
            Write-Host 'Skipping Intune data collection - tenant does not have required license'
        }
        #endregion Intune Licensed

        Write-Information "Built batch of $($Batch.Count) cache collection activities for tenant $TenantFilter"

        # Start orchestration for this tenant's cache collection
        $InputObject = [PSCustomObject]@{
            OrchestratorName = "CIPPDBCacheTenant_$TenantFilter"
            Batch            = @($Batch)
            SkipLog          = $true
        }

        if ($Item.TestRun -eq $true) {
            $InputObject | Add-Member -NotePropertyName PostExecution -NotePropertyValue @{
                FunctionName = 'CIPPDBTestsRun'
                Parameters   = @{
                    TenantFilter = $TenantFilter
                }
            }
        }

        $InstanceId = Start-NewOrchestration -FunctionName 'CIPPOrchestrator' -InputObject ($InputObject | ConvertTo-Json -Depth 5 -Compress)
        Write-Information "Started cache collection orchestration for $TenantFilter with ID = '$InstanceId'"
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Started cache collection orchestration with $($Batch.Count) activities. Instance ID: $InstanceId" -sev Info

        return @{
            InstanceId = $InstanceId
            BatchCount = $Batch.Count
            Message    = "Cache collection orchestration started for $TenantFilter"
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to start cache collection orchestration: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        throw $ErrorMessage
    }
}

function New-CIPPRestoreTask {
    [CmdletBinding()]
    param (
        $Task,
        $TenantFilter,
        $backup,
        $overwrite,
        $APINAME,
        $Headers
    )
    # Use Get-CIPPBackup which handles blob storage fetching
    $BackupData = Get-CIPPBackup -Type 'Scheduled' -Name $backup

    # If this is a blob-based backup, parse the Backup property to get the actual data structure
    if ($BackupData.BackupIsBlob -or $BackupData.BackupIsBlobLink) {
        try {
            $BackupData = $BackupData.Backup | ConvertFrom-Json
        } catch {
            Write-Warning "Failed to parse blob backup data: $($_.Exception.Message)"
        }
    }


    # Initialize restoration counters
    $restorationStats = @{
        'CustomVariables'   = @{ success = 0; failed = 0 }
        'Users'             = @{ success = 0; failed = 0 }
        'Groups'            = @{ success = 0; failed = 0 }
        'ConditionalAccess' = @{ success = 0; failed = 0 }
        'IntuneConfig'      = @{ success = 0; failed = 0 }
        'IntunCompliance'   = @{ success = 0; failed = 0 }
        'IntuneProtection'  = @{ success = 0; failed = 0 }
        'AntiSpam'          = @{ success = 0; failed = 0 }
        'AntiPhishing'      = @{ success = 0; failed = 0 }
        'WebhookAlerts'     = @{ success = 0; failed = 0 }
        'ScriptedAlerts'    = @{ success = 0; failed = 0 }
    }

    # Helper function to clean user object for Graph API - removes reference properties, nulls, and empty strings
    function Clean-GraphObject {
        param($Object, [switch]$ExcludeId)
        $excludeProps = @('password', 'passwordProfile', '@odata.type', 'manager', 'memberOf', 'createdOnBehalfOf', 'createdByAppId', 'deletedDateTime', 'authorizationInfo')
        if ($ExcludeId) {
            $excludeProps += @('id')
        }

        $cleaned = $Object | Select-Object * -ExcludeProperty $excludeProps
        $result = @{}

        foreach ($prop in $cleaned.PSObject.Properties) {
            $propValue = $prop.Value
            # Skip empty strings, nulls, and complex objects (except known-good arrays like businessPhones)
            if ($propValue -ne '' -and $null -ne $propValue) {
                # Skip complex objects/dictionaries but allow simple arrays
                if ($propValue -is [System.Collections.IDictionary]) {
                    continue
                }
                $result[$prop.Name] = $propValue
            }
        }

        return $result
    }

    $RestoreData = [System.Collections.Generic.List[string]]::new()

    switch ($Task) {
        'CippCustomVariables' {
            Write-Host "Restore Custom Variables for $TenantFilter"
            $ReplaceTable = Get-CIPPTable -TableName 'CippReplacemap'
            $Backup = if ($BackupData.CippCustomVariables -is [string]) { $BackupData.CippCustomVariables | ConvertFrom-Json } else { $BackupData.CippCustomVariables }

            $Tenant = Get-Tenants -TenantFilter $TenantFilter
            $CustomerId = $Tenant.customerId

            try {
                foreach ($variable in $Backup) {
                    $entity = @{
                        PartitionKey = $CustomerId
                        RowKey       = $variable.RowKey
                        Value        = $variable.Value
                        Description  = $variable.Description
                    }

                    try {
                        if ($overwrite) {
                            Add-CIPPAzDataTableEntity @ReplaceTable -Entity $entity -Force
                            Write-LogMessage -message "Restored custom variable $($variable.RowKey) from backup" -Sev 'info'
                            $restorationStats['CustomVariables'].success++
                            $RestoreData.Add("Restored custom variable $($variable.RowKey) from backup")
                        } else {
                            # Check if variable already exists
                            $existing = Get-CIPPAzDataTableEntity @ReplaceTable -Filter "PartitionKey eq '$CustomerId' and RowKey eq '$($variable.RowKey)'"
                            if (!$existing) {
                                Add-CIPPAzDataTableEntity @ReplaceTable -Entity $entity -Force
                                Write-LogMessage -message "Restored custom variable $($variable.RowKey) from backup" -Sev 'info'
                                $restorationStats['CustomVariables'].success++
                                $RestoreData.Add("Restored custom variable $($variable.RowKey) from backup")
                            } else {
                                Write-LogMessage -message "Custom variable $($variable.RowKey) already exists and overwrite is disabled" -Sev 'info'
                                $RestoreData.Add("Custom variable $($variable.RowKey) already exists and overwrite is disabled")
                            }
                        }
                    } catch {
                        $restorationStats['CustomVariables'].failed++
                        Write-LogMessage -message "Failed to restore custom variable $($variable.RowKey): $($_.Exception.Message)" -Sev 'Warning'
                        $RestoreData.Add("Failed to restore custom variable $($variable.RowKey)")
                    }
                }
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                $RestoreData.Add("Could not restore Custom Variables: $ErrorMessage")
                Write-LogMessage -Headers $Headers -API $APINAME -message "Could not restore Custom Variables: $ErrorMessage" -Sev 'Error'
            }
        }
        'users' {
            $currentUsers = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/users?$top=999&select=id,userPrincipalName' -tenantid $TenantFilter
            $backupUsers = if ($BackupData.users -is [string]) { $BackupData.users | ConvertFrom-Json } else { $BackupData.users }

            Write-Host "Restore users for $TenantFilter"
            Write-Information "User count in backup: $($backupUsers.Count)"
            $BackupUsers | ForEach-Object {
                try {
                    $userObject = $_
                    $UPN = $userObject.userPrincipalName

                    if ($overwrite) {
                        if ($userObject.id -in $currentUsers.id -or $userObject.userPrincipalName -in $currentUsers.userPrincipalName) {
                            # Patch existing user - clean object to remove reference properties, nulls, and empty strings
                            $cleanedUser = Clean-GraphObject -Object $userObject
                            $patchBody = $cleanedUser | ConvertTo-Json -Depth 100 -Compress
                            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/users/$($userObject.id)" -tenantid $TenantFilter -body $patchBody -type PATCH
                            Write-LogMessage -message "Restored $($UPN) from backup by patching the existing object." -Sev 'info'
                            $restorationStats['Users'].success++
                            $RestoreData.Add("The user existed. Restored $($UPN) from backup")
                        } else {
                            # Create new user - need to add password and clean object
                            $tempPassword = New-passwordString
                            # Remove reference properties that may not exist in target tenant, nulls, and empty strings
                            $cleanedUser = Clean-GraphObject -Object $userObject -ExcludeId
                            $cleanedUser['passwordProfile'] = @{
                                'forceChangePasswordNextSignIn' = $true
                                'password'                      = $tempPassword
                            }
                            $JSON = $cleanedUser | ConvertTo-Json -Depth 100 -Compress

                            $null = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/users' -tenantid $TenantFilter -body $JSON -type POST
                            # Try to wrap password in PwPush link
                            $displayPassword = $tempPassword
                            try {
                                $PasswordLink = New-PwPushLink -Payload $tempPassword
                                if ($PasswordLink) {
                                    $displayPassword = $PasswordLink
                                }
                            } catch {
                                # If PwPush fails, use plain password
                            }
                            Write-LogMessage -message "Restored $($UPN) from backup by creating a new object with temporary password. Password: $displayPassword" -Sev 'info' -tenant $TenantFilter
                            $restorationStats['Users'].success++
                            $RestoreData.Add("The user did not exist. Restored $($UPN) from backup with temporary password: $displayPassword")
                        }
                    }
                    if (!$overwrite) {
                        if ($userObject.id -notin $currentUsers.id -and $userObject.userPrincipalName -notin $currentUsers.userPrincipalName) {
                            # Create new user - need to add password and clean object
                            $tempPassword = New-passwordString
                            # Remove reference properties that may not exist in target tenant, nulls, and empty strings
                            $cleanedUser = Clean-GraphObject -Object $userObject -ExcludeId
                            $cleanedUser['passwordProfile'] = @{
                                'forceChangePasswordNextSignIn' = $true
                                'password'                      = $tempPassword
                            }
                            $JSON = $cleanedUser | ConvertTo-Json -Depth 100 -Compress
                            $null = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/users' -tenantid $TenantFilter -body $JSON -type POST
                            # Try to wrap password in PwPush link
                            $displayPassword = $tempPassword
                            try {
                                $PasswordLink = New-PwPushLink -Payload $tempPassword
                                if ($PasswordLink) {
                                    $displayPassword = $PasswordLink
                                }
                            } catch {
                                # If PwPush fails, use plain password
                            }
                            Write-LogMessage -message "Restored $($UPN) from backup with temporary password. Password: $displayPassword" -Sev 'info'
                            $restorationStats['Users'].success++
                            $RestoreData.Add("Restored $($UPN) from backup with temporary password: $displayPassword")
                        }
                    }
                } catch {
                    $restorationStats['Users'].failed++
                    $ErrorMessage = Get-CippException -Exception $_
                    $RestoreData.Add("Could not restore user $($UPN): $($ErrorMessage.NormalizedError) ")
                    Write-LogMessage -Headers $Headers -API $APINAME -message "Could not restore user $($UPN): $($ErrorMessage.NormalizedError) " -Sev 'Error' -LogData $ErrorMessage
                }
            }
        }
        'groups' {
            Write-Host "Restore groups for $TenantFilter"
            $backupGroups = if ($BackupData.groups -is [string]) { $BackupData.groups | ConvertFrom-Json } else { $BackupData.groups }
            $Groups = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$top=999' -tenantid $TenantFilter
            $BackupGroups | ForEach-Object {
                try {
                    $JSON = $_ | ConvertTo-Json -Depth 100 -Compress
                    $DisplayName = $_.displayName
                    if ($overwrite) {
                        if ($_.id -in $Groups.id) {
                            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/groups/$($_.id)" -tenantid $TenantFilter -body $JSON -type PATCH
                            Write-LogMessage -message "Restored $DisplayName from backup by patching the existing object." -Sev 'info'
                            $restorationStats['Groups'].success++
                            $RestoreData.Add("The group existed. Restored $DisplayName from backup")
                        } else {
                            $null = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/groups' -tenantid $TenantFilter -body $JSON -type POST
                            Write-LogMessage -message "Restored $DisplayName from backup" -Sev 'info'
                            $restorationStats['Groups'].success++
                            $RestoreData.Add("Restored $DisplayName from backup")
                        }
                    }
                    if (!$overwrite) {
                        if ($_.id -notin $Groups.id) {
                            $null = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/groups' -tenantid $TenantFilter -body $JSON -type POST
                            Write-LogMessage -message "Restored $DisplayName from backup" -Sev 'info'
                            $restorationStats['Groups'].success++
                            $RestoreData.Add("Restored $DisplayName from backup")
                        } else {
                            Write-LogMessage -message "Group $DisplayName already exists in tenant $TenantFilter and overwrite is disabled" -Sev 'info'
                            $RestoreData.Add("Group $DisplayName already exists in tenant $TenantFilter and overwrite is disabled")
                        }
                    }
                } catch {
                    $restorationStats['Groups'].failed++
                    $ErrorMessage = Get-CippException -Exception $_
                    $RestoreData.Add("Could not restore group $DisplayName : $($ErrorMessage.NormalizedError) ")
                    Write-LogMessage -Headers $Headers -API $APINAME -message "Could not restore group $DisplayName : $($ErrorMessage.NormalizedError) " -Sev 'Error' -LogData $ErrorMessage
                }
            }
        }
        'ca' {
            Write-Host "Restore Conditional Access Policies for $TenantFilter"
            $BackupCAPolicies = if ($BackupData.ca -is [string]) { $BackupData.ca | ConvertFrom-Json } else { $BackupData.ca }
            $BackupCAPolicies | ForEach-Object {
                $JSON = $_
                try {
                    $null = New-CIPPCAPolicy -replacePattern 'displayName' -Overwrite $overwrite -TenantFilter $TenantFilter -state 'donotchange' -RawJSON $JSON -APIName 'CIPP Restore' -ErrorAction SilentlyContinue
                    $restorationStats['ConditionalAccess'].success++
                    $RestoreData.Add('Restored Conditional Access policy from backup')
                } catch {
                    $restorationStats['ConditionalAccess'].failed++
                    $ErrorMessage = Get-CippException -Exception $_
                    $RestoreData.Add("Could not restore Conditional Access Policy $DisplayName : $($ErrorMessage.NormalizedError) ")
                    Write-LogMessage -Headers $Headers -API $APINAME -message "Could not restore Conditional Access Policy $DisplayName : $($ErrorMessage.NormalizedError) " -Sev 'Error' -LogData $ErrorMessage
                }
            }
        }
        'intuneconfig' {
            $BackupConfig = if ($BackupData.intuneconfig -is [string]) { $BackupData.intuneconfig | ConvertFrom-Json } else { $BackupData.intuneconfig }
            foreach ($backup in $backupConfig) {
                try {
                    $null = Set-CIPPIntunePolicy -TemplateType $backup.Type -TenantFilter $TenantFilter -DisplayName $backup.DisplayName -Description $backup.Description -RawJSON ($backup.TemplateJson) -Headers $Headers -APINAME $APINAME -ErrorAction SilentlyContinue
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    $RestoreData.Add("Could not restore Intune Configuration $DisplayName : $($ErrorMessage.NormalizedError) ")
                    Write-LogMessage -Headers $Headers -API $APINAME -message "Could not restore Intune Configuration $DisplayName : $($ErrorMessage.NormalizedError) " -Sev 'Error' -LogData $ErrorMessage
                }
            }
            #Convert the manual method to a function
        }
        'intunecompliance' {
            $BackupConfig = if ($BackupData.intunecompliance -is [string]) { $BackupData.intunecompliance | ConvertFrom-Json } else { $BackupData.intunecompliance }
            foreach ($backup in $backupConfig) {
                try {
                    $null = Set-CIPPIntunePolicy -TemplateType $backup.Type -TenantFilter $TenantFilter -DisplayName $backup.DisplayName -Description $backup.Description -RawJSON ($backup.TemplateJson) -Headers $Headers -APINAME $APINAME -ErrorAction SilentlyContinue
                    $restorationStats['IntuneConfig'].success++
                    $RestoreData.Add('Restored Intune configuration from backup')
                } catch {
                    $restorationStats['IntuneConfig'].failed++
                    $ErrorMessage = Get-CippException -Exception $_
                    $RestoreData.Add("Could not restore Intune Compliance $DisplayName : $($ErrorMessage.NormalizedError) ")
                    Write-LogMessage -Headers $Headers -API $APINAME -message "Could not restore Intune Configuration $DisplayName : $($ErrorMessage.NormalizedError) " -Sev 'Error' -LogData $ErrorMessage
                }
            }

        }

        'intuneprotection' {
            $BackupConfig = if ($BackupData.intuneprotection -is [string]) { $BackupData.intuneprotection | ConvertFrom-Json } else { $BackupData.intuneprotection }
            foreach ($backup in $backupConfig) {
                try {
                    $null = Set-CIPPIntunePolicy -TemplateType $backup.Type -TenantFilter $TenantFilter -DisplayName $backup.DisplayName -Description $backup.Description -RawJSON ($backup.TemplateJson) -Headers $Headers -APINAME $APINAME -ErrorAction SilentlyContinue
                    $restorationStats['IntuneProtection'].success++
                    $RestoreData.Add('Restored Intune protection policy from backup')
                } catch {
                    $restorationStats['IntuneProtection'].failed++
                    $ErrorMessage = Get-CippException -Exception $_
                    $RestoreData.Add("Could not restore Intune Protection $DisplayName : $($ErrorMessage.NormalizedError) ")
                    Write-LogMessage -Headers $Headers -API $APINAME -message "Could not restore Intune Configuration $DisplayName : $($ErrorMessage.NormalizedError) " -Sev 'Error' -LogData $ErrorMessage
                }
            }

        }

        'antispam' {
            try {
                $BackupConfig = if ($BackupData.antispam -is [string]) { $BackupData.antispam | ConvertFrom-Json } else { $BackupData.antispam }
                if ($BackupConfig -is [string]) { $BackupConfig = $BackupConfig | ConvertFrom-Json }
                $BackupPolicies = $BackupConfig.policies
                $BackupRules = $BackupConfig.rules
                $CurrentPolicies = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-HostedContentFilterPolicy' | Select-Object * -ExcludeProperty *odata*, *data.type*
                $CurrentRules = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-HostedContentFilterRule' | Select-Object * -ExcludeProperty *odata*, *data.type*
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $RestoreData.Add("Could not obtain Anti-Spam Configuration: $($ErrorMessage.NormalizedError) ")
                Write-LogMessage -Headers $Headers -API $APINAME -message "Could not obtain Anti-Spam Configuration: $($ErrorMessage.NormalizedError) " -Sev 'Error' -LogData $ErrorMessage
            }

            $policyparams = @(
                'AddXHeaderValue',
                'AdminDisplayName',
                'AllowedSenderDomains',
                'AllowedSenders',
                'BlockedSenderDomains',
                'BlockedSenders',
                'BulkQuarantineTag',
                'BulkSpamAction',
                'BulkThreshold',
                'DownloadLink',
                'EnableEndUserSpamNotifications',
                'EnableLanguageBlockList',
                'EnableRegionBlockList',
                'EndUserSpamNotificationCustomFromAddress',
                'EndUserSpamNotificationCustomFromName',
                'EndUserSpamNotificationCustomSubject',
                'EndUserSpamNotificationFrequency',
                'EndUserSpamNotificationLanguage',
                'EndUserSpamNotificationLimit',
                'HighConfidencePhishAction',
                'HighConfidencePhishQuarantineTag',
                'HighConfidenceSpamAction',
                'HighConfidenceSpamQuarantineTag',
                'IncreaseScoreWithBizOrInfoUrls',
                'IncreaseScoreWithImageLinks',
                'IncreaseScoreWithNumericIps',
                'IncreaseScoreWithRedirectToOtherPort',
                'InlineSafetyTipsEnabled',
                'IntraOrgFilterState',
                'LanguageBlockList',
                'MarkAsSpamBulkMail',
                'MarkAsSpamEmbedTagsInHtml',
                'MarkAsSpamEmptyMessages',
                'MarkAsSpamFormTagsInHtml',
                'MarkAsSpamFramesInHtml',
                'MarkAsSpamFromAddressAuthFail',
                'MarkAsSpamJavaScriptInHtml',
                'MarkAsSpamNdrBackscatter',
                'MarkAsSpamObjectTagsInHtml',
                'MarkAsSpamSensitiveWordList',
                'MarkAsSpamSpfRecordHardFail',
                'MarkAsSpamWebBugsInHtml',
                'ModifySubjectValue',
                'PhishQuarantineTag',
                'PhishSpamAction',
                'PhishZapEnabled',
                'QuarantineRetentionPeriod',
                'RedirectToRecipients',
                'RegionBlockList',
                'SpamAction',
                'SpamQuarantineTag',
                'SpamZapEnabled',
                'TestModeAction',
                'TestModeBccToRecipients'
            )

            $ruleparams = @(
                'Name',
                'HostedContentFilterPolicy',
                'Comments',
                'Enabled',
                'ExceptIfRecipientDomainIs',
                'ExceptIfSentTo',
                'ExceptIfSentToMemberOf',
                'Priority',
                'RecipientDomainIs',
                'SentTo',
                'SentToMemberOf'
            )

            foreach ($policy in $BackupPolicies) {
                try {
                    if ($policy.Identity -in $CurrentPolicies.Identity) {
                        if ($overwrite) {
                            $cmdparams = @{
                                Identity = $policy.Identity
                            }

                            foreach ($param in $policyparams) {
                                if ($policy.PSObject.Properties[$param]) {
                                    if ($param -eq 'IntraOrgFilterState' -and $policy.$param -eq 'Default') {
                                        $cmdparams[$param] = 'HighConfidencePhish'
                                    } else {
                                        $cmdparams[$param] = $policy.$param
                                    }
                                }
                            }

                            $null = New-ExoRequest -TenantId $Tenantfilter -cmdlet 'Set-HostedContentFilterPolicy' -cmdparams $cmdparams -UseSystemMailbox $true

                            Write-LogMessage -message "Restored $($policy.Identity) from backup" -Sev 'info'
                            $restorationStats['AntiSpam'].success++
                            $RestoreData.Add("Restored $($policy.Identity) from backup.")
                        }
                    } else {
                        $cmdparams = @{
                            Name = $policy.Name
                        }

                        foreach ($param in $policyparams) {
                            if ($policy.PSObject.Properties[$param]) {
                                if ($param -eq 'IntraOrgFilterState' -and $policy.$param -eq 'Default') {
                                    $cmdparams[$param] = 'HighConfidencePhish'
                                } else {
                                    $cmdparams[$param] = $policy.$param
                                }
                            }
                        }

                        $null = New-ExoRequest -TenantId $Tenantfilter -cmdlet 'New-HostedContentFilterPolicy' -cmdparams $cmdparams -UseSystemMailbox $true

                        Write-LogMessage -message "Restored $($policy.Identity) from backup" -Sev 'info'
                        $restorationStats['AntiSpam'].success++
                        $RestoreData.Add("Restored $($policy.Identity) from backup.")
                    }
                } catch {
                    $restorationStats['AntiSpam'].failed++
                    $ErrorMessage = Get-CippException -Exception $_
                    $RestoreData.Add("Could not restore Anti-spam policy $($policy.Identity) : $($ErrorMessage.NormalizedError) ")
                    Write-LogMessage -Headers $Headers -API $APINAME -message "Could not restore Anti-spam policy $($policy.Identity) : $($ErrorMessage.NormalizedError) " -Sev 'Error' -LogData $ErrorMessage
                }
            }

            foreach ($rule in $BackupRules) {
                try {
                    if ($rule.Identity -in $CurrentRules.Identity) {
                        if ($overwrite) {
                            $cmdparams = @{
                                Identity = $rule.Identity
                            }

                            foreach ($param in $ruleparams) {
                                if ($rule.PSObject.Properties[$param]) {
                                    if ($param -eq 'Enabled') {
                                        $cmdparams[$param] = if ($rule.State -eq 'Enabled') { $true } else { $false }
                                    } else {
                                        $cmdparams[$param] = $rule.$param
                                    }
                                }
                            }

                            $null = New-ExoRequest -TenantId $Tenantfilter -cmdlet 'Set-HostedContentFilterRule' -cmdparams $cmdparams -UseSystemMailbox $true

                            Write-LogMessage -message "Restored $($rule.Identity) from backup" -Sev 'info'
                            $restorationStats['AntiSpam'].success++
                            $RestoreData.Add("Restored $($rule.Identity) from backup.")
                        }
                    } else {
                        $cmdparams = @{
                            Name = $rule.Name
                        }

                        foreach ($param in $ruleparams) {
                            if ($rule.PSObject.Properties[$param]) {
                                if ($param -eq 'Enabled') {
                                    $cmdparams[$param] = if ($rule.State -eq 'Enabled') { $true } else { $false }
                                } else {
                                    $cmdparams[$param] = $rule.$param
                                }
                            }
                        }

                        $null = New-ExoRequest -TenantId $Tenantfilter -cmdlet 'New-HostedContentFilterRule' -cmdparams $cmdparams -UseSystemMailbox $true

                        Write-LogMessage -message "Restored $($rule.Identity) from backup" -Sev 'info'
                        $restorationStats['AntiSpam'].success++
                        $RestoreData.Add("Restored $($rule.Identity) from backup.")
                    }
                } catch {
                    $restorationStats['AntiSpam'].failed++
                    $ErrorMessage = Get-CippException -Exception $_
                    $RestoreData.Add("Could not restore Anti-spam rule $($rule.Identity) : $($ErrorMessage.NormalizedError) ")
                    Write-LogMessage -Headers $Headers -API $APINAME -message "Could not restore Anti-spam rule $($rule.Identity) : $($ErrorMessage.NormalizedError) " -Sev 'Error' -LogData $ErrorMessage
                }
            }
        }

        'antiphishing' {
            try {
                $BackupConfig = if ($BackupData.antiphishing -is [string]) { $BackupData.antiphishing | ConvertFrom-Json } else { $BackupData.antiphishing }
                if ($BackupConfig -is [string]) { $BackupConfig = $BackupConfig | ConvertFrom-Json }
                $BackupPolicies = $BackupConfig.policies
                $BackupRules = $BackupConfig.rules
                $CurrentPolicies = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-AntiPhishPolicy' | Select-Object * -ExcludeProperty *odata*, *data.type*
                $CurrentRules = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-AntiPhishRule' | Select-Object * -ExcludeProperty *odata*, *data.type*
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $RestoreData.Add("Could not obtain Anti-Phishing Configuration: $($ErrorMessage.NormalizedError) ")
                Write-LogMessage -Headers $Headers -API $APINAME -message "Could not obtain Anti-Phishing Configuration: $($ErrorMessage.NormalizedError) " -Sev 'Error' -LogData $ErrorMessage
            }

            $policyparams = @(
                'AdminDisplayName',
                'AuthenticationFailAction',
                'DmarcQuarantineAction',
                'DmarcRejectAction',
                'EnableFirstContactSafetyTips',
                'EnableMailboxIntelligence',
                'EnableMailboxIntelligenceProtection',
                'EnableOrganizationDomainsProtection',
                'EnableSimilarDomainsSafetyTips',
                'EnableSimilarUsersSafetyTips',
                'EnableSpoofIntelligence',
                'EnableTargetedDomainsProtection',
                'EnableTargetedUserProtection',
                'EnableUnauthenticatedSender',
                'EnableUnusualCharactersSafetyTips',
                'EnableViaTag',
                'ExcludedDomains',
                'ExcludedSenders',
                'HonorDmarcPolicy',
                'ImpersonationProtectionState',
                'MailboxIntelligenceProtectionAction',
                'MailboxIntelligenceProtectionActionRecipients',
                'MailboxIntelligenceQuarantineTag',
                'PhishThresholdLevel',
                'SimilarUsersSafetyTipsCustomText',
                'SpoofQuarantineTag',
                'TargetedDomainActionRecipients',
                'TargetedDomainProtectionAction',
                'TargetedDomainQuarantineTag',
                'TargetedDomainsToProtect',
                'TargetedUserActionRecipients',
                'TargetedUserProtectionAction',
                'TargetedUserQuarantineTag',
                'TargetedUsersToProtect'
            )

            $ruleparams = @(
                'Name',
                'AntiPhishPolicy',
                'Comments',
                'Enabled',
                'ExceptIfRecipientDomainIs',
                'ExceptIfSentTo',
                'ExceptIfSentToMemberOf',
                'Priority',
                'RecipientDomainIs',
                'SentTo',
                'SentToMemberOf'
            )

            foreach ($policy in $BackupPolicies) {
                try {
                    if ($policy.Identity -in $CurrentPolicies.Identity) {
                        if ($overwrite) {
                            $cmdparams = @{
                                Identity = $policy.Identity
                            }

                            foreach ($param in $policyparams) {
                                if ($policy.PSObject.Properties[$param]) {
                                    $cmdparams[$param] = $policy.$param
                                }
                            }

                            $null = New-ExoRequest -TenantId $Tenantfilter -cmdlet 'Set-AntiPhishPolicy' -cmdparams $cmdparams -UseSystemMailbox $true

                            Write-LogMessage -message "Restored $($policy.Identity) from backup" -Sev 'info'
                            $restorationStats['AntiPhishing'].success++
                            $RestoreData.Add("Restored $($policy.Identity) from backup.")
                        }
                    } else {
                        $cmdparams = @{
                            Name = $policy.Name
                        }

                        foreach ($param in $policyparams) {
                            if ($policy.PSObject.Properties[$param]) {
                                $cmdparams[$param] = $policy.$param
                            }
                        }

                        $null = New-ExoRequest -TenantId $Tenantfilter -cmdlet 'New-AntiPhishPolicy' -cmdparams $cmdparams -UseSystemMailbox $true

                        Write-LogMessage -message "Restored $($policy.Identity) from backup" -Sev 'info'
                        $restorationStats['AntiPhishing'].success++
                        $RestoreData.Add("Restored $($policy.Identity) from backup.")
                    }
                } catch {
                    $restorationStats['AntiPhishing'].failed++
                    $ErrorMessage = Get-CippException -Exception $_
                    $RestoreData.Add("Could not restore Anti-phishing policy $($policy.Identity) : $($ErrorMessage.NormalizedError) ")
                    Write-LogMessage -Headers $Headers -API $APINAME -message "Could not restore Anti-phishing policy $($policy.Identity) : $($ErrorMessage.NormalizedError) " -Sev 'Error' -LogData $ErrorMessage
                }
            }

            foreach ($rule in $BackupRules) {
                try {
                    if ($rule.Identity -in $CurrentRules.Identity) {
                        if ($overwrite) {
                            $cmdparams = @{
                                Identity = $rule.Identity
                            }

                            foreach ($param in $ruleparams) {
                                if ($rule.PSObject.Properties[$param]) {
                                    if ($param -eq 'Enabled') {
                                        $cmdparams[$param] = if ($rule.State -eq 'Enabled') { $true } else { $false }
                                    } else {
                                        $cmdparams[$param] = $rule.$param
                                    }
                                }
                            }

                            $null = New-ExoRequest -TenantId $Tenantfilter -cmdlet 'Set-AntiPhishRule' -cmdparams $cmdparams -UseSystemMailbox $true

                            Write-LogMessage -message "Restored $($rule.Identity) from backup" -Sev 'info'
                            $restorationStats['AntiPhishing'].success++
                            $RestoreData.Add("Restored $($rule.Identity) from backup.")
                        }
                    } else {
                        $cmdparams = @{
                            Name = $rule.Name
                        }

                        foreach ($param in $ruleparams) {
                            if ($rule.PSObject.Properties[$param]) {
                                if ($param -eq 'Enabled') {
                                    $cmdparams[$param] = if ($rule.State -eq 'Enabled') { $true } else { $false }
                                } else {
                                    $cmdparams[$param] = $rule.$param
                                }
                            }
                        }

                        $null = New-ExoRequest -TenantId $Tenantfilter -cmdlet 'New-AntiPhishRule' -cmdparams $cmdparams -UseSystemMailbox $true

                        Write-LogMessage -message "Restored $($rule.Identity) from backup" -Sev 'info'
                        $restorationStats['AntiPhishing'].success++
                        $RestoreData.Add("Restored $($rule.Identity) from backup.")
                    }
                } catch {
                    $restorationStats['AntiPhishing'].failed++
                    $ErrorMessage = Get-CippException -Exception $_
                    $RestoreData.Add("Could not restore Anti-phishing rule $($rule.Identity) : $($ErrorMessage.NormalizedError) ")
                    Write-LogMessage -Headers $Headers -API $APINAME -message "Could not restore Anti-phishing rule $($rule.Identity) : $($ErrorMessage.NormalizedError) " -Sev 'Error' -LogData $ErrorMessage
                }
            }
        }
        'CippWebhookAlerts' {
            Write-Host "Restore Webhook Alerts for $TenantFilter"
            $WebhookTable = Get-CIPPTable -TableName 'WebhookRules'
            $Backup = if ($BackupData.CippWebhookAlerts -is [string]) { $BackupData.CippWebhookAlerts | ConvertFrom-Json } else { $BackupData.CippWebhookAlerts }
            try {
                Add-CIPPAzDataTableEntity @WebhookTable -Entity $Backup -Force
                $restorationStats['WebhookAlerts'].success++
                $RestoreData.Add('Restored Webhook Alerts from backup')
            } catch {
                $restorationStats['WebhookAlerts'].failed++
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                $RestoreData.Add("Could not restore Webhook Alerts $ErrorMessage")
            }
        }
        'CippScriptedAlerts' {
            Write-Host "Restore Scripted Alerts for $TenantFilter"
            $ScheduledTasks = Get-CIPPTable -TableName 'ScheduledTasks'
            $Backup = if ($BackupData.CippScriptedAlerts -is [string]) { $BackupData.CippScriptedAlerts | ConvertFrom-Json } else { $BackupData.CippScriptedAlerts }
            try {
                Add-CIPPAzDataTableEntity @ScheduledTasks -Entity $Backup -Force
                $restorationStats['ScriptedAlerts'].success++
                $RestoreData.Add('Restored Scripted Alerts from backup')
            } catch {
                $restorationStats['ScriptedAlerts'].failed++
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                $RestoreData.Add("Could not restore Scripted Alerts $ErrorMessage ")
            }
        }
    }

    # Build summary message
    $summaryParts = @()
    $successCount = 0
    $failureCount = 0

    foreach ($type in $restorationStats.Keys) {
        $successCount += $restorationStats[$type].success
        $failureCount += $restorationStats[$type].failed

        if ($restorationStats[$type].success -gt 0) {
            $pluralForm = if ($restorationStats[$type].success -eq 1) { $type.TrimEnd('s') } else { $type }
            $summaryParts += "$($restorationStats[$type].success) $pluralForm"
        }
    }

    if ($summaryParts.Count -gt 0) {
        $summary = 'Restored: ' + ($summaryParts -join ', ') + ' from backup'
        if ($failureCount -gt 0) {
            $summary += " ($failureCount items failed)"
        }
        $RestoreData.Add($summary)
    } elseif ($failureCount -eq 0 -and $successCount -eq 0) {
        $RestoreData.Add('No items were restored from backup.')
    }

    return $RestoreData
}

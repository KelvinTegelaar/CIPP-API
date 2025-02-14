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
    $Table = Get-CippTable -tablename 'ScheduledBackup'
    $BackupData = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$backup'"
    $RestoreData = switch ($Task) {
        'users' {
            $currentUsers = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/users?$top=999&select=id,userPrincipalName' -tenantid $TenantFilter
            $backupUsers = $BackupData.users | ConvertFrom-Json
            $BackupUsers | ForEach-Object {
                try {
                    $JSON = $_ | ConvertTo-Json -Depth 100 -Compress
                    $DisplayName = $_.displayName
                    $UPN = $_.userPrincipalName
                    if ($overwrite) {
                        if ($_.id -in $currentUsers.id) {
                            New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/users/$($_.id)" -tenantid $TenantFilter -body $JSON -type PATCH
                            Write-LogMessage -message "Restored $($UPN) from backup by patching the existing object." -Sev 'info'
                            "The user existed. Restored $($UPN) from backup"
                        } else {
                            New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/users' -tenantid $TenantFilter -body $JSON -type POST
                            Write-LogMessage -message "Restored $($UPN) from backup by creating a new object." -Sev 'info'
                            "The user did not exist. Restored $($UPN) from backup"
                        }
                    }
                    if (!$overwrite) {
                        if ($_.id -notin $backupUsers.id) {
                            New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/users' -tenantid $TenantFilter -body $JSON -type POST
                            Write-LogMessage -message "Restored $($UPN) from backup" -Sev 'info'
                            "Restored $($UPN) from backup"
                        } else {
                            Write-LogMessage -message "User $($UPN) already exists in tenant $TenantFilter and overwrite is disabled" -Sev 'info'
                            "User $($UPN) already exists in tenant $TenantFilter and overwrite is disabled"
                        }
                    }
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    "Could not restore user $($UPN): $($ErrorMessage.NormalizedError) "
                    Write-LogMessage -Headers $Headers -API $APINAME -message "Could not restore user $($UPN): $($ErrorMessage.NormalizedError) " -Sev 'Error' -LogData $ErrorMessage
                }
            }
        }
        'groups' {
            Write-Host "Restore groups for $TenantFilter"
            $backupGroups = $BackupData.groups | ConvertFrom-Json
            $Groups = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/groups?$top=999' -tenantid $TenantFilter
            $BackupGroups | ForEach-Object {
                try {
                    $JSON = $_ | ConvertTo-Json -Depth 100 -Compress
                    $DisplayName = $_.displayName
                    if ($overwrite) {
                        if ($_.id -in $Groups.id) {
                            New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/groups/$($_.id)" -tenantid $TenantFilter -body $JSON -type PATCH
                            Write-LogMessage -message "Restored $DisplayName from backup by patching the existing object." -Sev 'info'
                            "The group existed. Restored $DisplayName from backup"
                        } else {
                            New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/groups' -tenantid $TenantFilter -body $JSON -type POST
                            Write-LogMessage -message "Restored $DisplayName from backup" -Sev 'info'
                            "Restored $DisplayName from backup"
                        }
                    }
                    if (!$overwrite) {
                        if ($_.id -notin $Groups.id) {
                            New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/groups' -tenantid $TenantFilter -body $JSON -type POST
                            Write-LogMessage -message "Restored $DisplayName from backup" -Sev 'info'
                            "Restored $DisplayName from backup"
                        } else {
                            Write-LogMessage -message "Group $DisplayName already exists in tenant $TenantFilter and overwrite is disabled" -Sev 'info'
                            "Group $DisplayName already exists in tenant $TenantFilter and overwrite is disabled"
                        }
                    }
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    "Could not restore group $DisplayName : $($ErrorMessage.NormalizedError) "
                    Write-LogMessage -Headers $Headers -API $APINAME -message "Could not restore group $DisplayName : $($ErrorMessage.NormalizedError) " -Sev 'Error' -LogData $ErrorMessage
                }
            }
        }
        'ca' {
            Write-Host "Restore Conditional Access Policies for $TenantFilter"
            $BackupCAPolicies = $BackupData.ca | ConvertFrom-Json
            $BackupCAPolicies | ForEach-Object {
                $JSON = $_
                try {
                    New-CIPPCAPolicy -replacePattern 'displayName' -Overwrite $overwrite -TenantFilter $TenantFilter -state 'donotchange' -RawJSON $JSON -APIName 'CIPP Restore' -ErrorAction SilentlyContinue
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    "Could not restore Conditional Access Policy $DisplayName : $($ErrorMessage.NormalizedError) "
                    Write-LogMessage -Headers $Headers -API $APINAME -message "Could not restore Conditional Access Policy $DisplayName : $($ErrorMessage.NormalizedError) " -Sev 'Error' -LogData $ErrorMessage
                }
            }
        }
        'intuneconfig' {
            $BackupConfig = $BackupData.intuneconfig | ConvertFrom-Json
            foreach ($backup in $backupConfig) {
                try {
                    Set-CIPPIntunePolicy -TemplateType $backup.Type -TenantFilter $TenantFilter -DisplayName $backup.DisplayName -Description $backup.Description -RawJSON ($backup.TemplateJson) -Headers $Headers -APINAME $APINAME -ErrorAction SilentlyContinue
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    "Could not restore Intune Configuration $DisplayName : $($ErrorMessage.NormalizedError) "
                    Write-LogMessage -Headers $Headers -API $APINAME -message "Could not restore Intune Configuration $DisplayName : $($ErrorMessage.NormalizedError) " -Sev 'Error' -LogData $ErrorMessage
                }
            }
            #Convert the manual method to a function
        }
        'intunecompliance' {
            $BackupConfig = $BackupData.intunecompliance | ConvertFrom-Json
            foreach ($backup in $backupConfig) {
                try {
                    Set-CIPPIntunePolicy -TemplateType $backup.Type -TenantFilter $TenantFilter -DisplayName $backup.DisplayName -Description $backup.Description -RawJSON ($backup.TemplateJson) -Headers $Headers -APINAME $APINAME -ErrorAction SilentlyContinue
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    "Could not restore Intune Compliance $DisplayName : $($ErrorMessage.NormalizedError) "
                    Write-LogMessage -Headers $Headers -API $APINAME -message "Could not restore Intune Configuration $DisplayName : $($ErrorMessage.NormalizedError) " -Sev 'Error' -LogData $ErrorMessage
                }
            }

        }

        'intuneprotection' {
            $BackupConfig = $BackupData.intuneprotection | ConvertFrom-Json
            foreach ($backup in $backupConfig) {
                try {
                    Set-CIPPIntunePolicy -TemplateType $backup.Type -TenantFilter $TenantFilter -DisplayName $backup.DisplayName -Description $backup.Description -RawJSON ($backup.TemplateJson) -Headers $Headers -APINAME $APINAME -ErrorAction SilentlyContinue
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    "Could not restore Intune Protection $DisplayName : $($ErrorMessage.NormalizedError) "
                    Write-LogMessage -Headers $Headers -API $APINAME -message "Could not restore Intune Configuration $DisplayName : $($ErrorMessage.NormalizedError) " -Sev 'Error' -LogData $ErrorMessage
                }
            }

        }

        'antispam' {
            try {
                $BackupConfig = $BackupData.antispam | ConvertFrom-Json | ConvertFrom-Json
                $BackupPolicies = $BackupConfig.policies
                $BackupRules = $BackupConfig.rules
                $CurrentPolicies = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-HostedContentFilterPolicy' | Select-Object * -ExcludeProperty *odata*, *data.type*
                $CurrentRules = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-HostedContentFilterRule' | Select-Object * -ExcludeProperty *odata*, *data.type*
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                "Could not obtain Anti-Spam Configuration: $($ErrorMessage.NormalizedError) "
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

                            New-ExoRequest -TenantId $Tenantfilter -cmdlet 'Set-HostedContentFilterPolicy' -cmdparams $cmdparams -UseSystemMailbox $true

                            Write-LogMessage -message "Restored $($policy.Identity) from backup" -Sev 'info'
                            "Restored $($policy.Identity) from backup."
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

                        New-ExoRequest -TenantId $Tenantfilter -cmdlet 'New-HostedContentFilterPolicy' -cmdparams $cmdparams -UseSystemMailbox $true

                        Write-LogMessage -message "Restored $($policy.Identity) from backup" -Sev 'info'
                        "Restored $($policy.Identity) from backup."
                    }
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    "Could not restore Anti-spam policy $($policy.Identity) : $($ErrorMessage.NormalizedError) "
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

                            New-ExoRequest -TenantId $Tenantfilter -cmdlet 'Set-HostedContentFilterRule' -cmdparams $cmdparams -UseSystemMailbox $true

                            Write-LogMessage -message "Restored $($rule.Identity) from backup" -Sev 'info'
                            "Restored $($rule.Identity) from backup."
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

                        New-ExoRequest -TenantId $Tenantfilter -cmdlet 'New-HostedContentFilterRule' -cmdparams $cmdparams -UseSystemMailbox $true

                        Write-LogMessage -message "Restored $($rule.Identity) from backup" -Sev 'info'
                        "Restored $($rule.Identity) from backup."
                    }
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    "Could not restore Anti-spam rule $($rule.Identity) : $($ErrorMessage.NormalizedError) "
                    Write-LogMessage -Headers $Headers -API $APINAME -message "Could not restore Anti-spam rule $($rule.Identity) : $($ErrorMessage.NormalizedError) " -Sev 'Error' -LogData $ErrorMessage
                }
            }
        }

        'antiphishing' {
            try {
                $BackupConfig = $BackupData.antiphishing | ConvertFrom-Json | ConvertFrom-Json
                $BackupPolicies = $BackupConfig.policies
                $BackupRules = $BackupConfig.rules
                $CurrentPolicies = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-AntiPhishPolicy' | Select-Object * -ExcludeProperty *odata*, *data.type*
                $CurrentRules = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-AntiPhishRule' | Select-Object * -ExcludeProperty *odata*, *data.type*
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                "Could not obtain Anti-Phishing Configuration: $($ErrorMessage.NormalizedError) "
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

                            New-ExoRequest -TenantId $Tenantfilter -cmdlet 'Set-AntiPhishPolicy' -cmdparams $cmdparams -UseSystemMailbox $true

                            Write-LogMessage -message "Restored $($policy.Identity) from backup" -Sev 'info'
                            "Restored $($policy.Identity) from backup."
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

                        New-ExoRequest -TenantId $Tenantfilter -cmdlet 'New-AntiPhishPolicy' -cmdparams $cmdparams -UseSystemMailbox $true

                        Write-LogMessage -message "Restored $($policy.Identity) from backup" -Sev 'info'
                        "Restored $($policy.Identity) from backup."
                    }
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    "Could not restore Anti-phishing policy $($policy.Identity) : $($ErrorMessage.NormalizedError) "
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

                            New-ExoRequest -TenantId $Tenantfilter -cmdlet 'Set-AntiPhishRule' -cmdparams $cmdparams -UseSystemMailbox $true

                            Write-LogMessage -message "Restored $($rule.Identity) from backup" -Sev 'info'
                            "Restored $($rule.Identity) from backup."
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

                        New-ExoRequest -TenantId $Tenantfilter -cmdlet 'New-AntiPhishRule' -cmdparams $cmdparams -UseSystemMailbox $true

                        Write-LogMessage -message "Restored $($rule.Identity) from backup" -Sev 'info'
                        "Restored $($rule.Identity) from backup."
                    }
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    "Could not restore Anti-phishing rule $($rule.Identity) : $($ErrorMessage.NormalizedError) "
                    Write-LogMessage -Headers $Headers -API $APINAME -message "Could not restore Anti-phishing rule $($rule.Identity) : $($ErrorMessage.NormalizedError) " -Sev 'Error' -LogData $ErrorMessage
                }
            }
        }

        'CippWebhookAlerts' {
            Write-Host "Restore Webhook Alerts for $TenantFilter"
            $WebhookTable = Get-CIPPTable -TableName 'WebhookRules'
            $Backup = $BackupData.CippWebhookAlerts | ConvertFrom-Json
            try {
                Add-CIPPAzDataTableEntity @WebhookTable -Entity $Backup -Force
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                "Could not restore Webhook Alerts $ErrorMessage"
            }
        }
        'CippScriptedAlerts' {
            Write-Host "Restore Scripted Alerts for $TenantFilter"
            $ScheduledTasks = Get-CIPPTable -TableName 'ScheduledTasks'
            $Backup = $BackupData.CippScriptedAlerts | ConvertFrom-Json
            try {
                Add-CIPPAzDataTableEntity @ScheduledTasks -Entity $Backup -Force
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                "Could not restore Scripted Alerts $ErrorMessage "
            }
        }
        'CippStandards' {
            Write-Host "Restore Standards for $TenantFilter"
            $Table = Get-CippTable -tablename 'standards'
            $StandardsBackup = $BackupData.CippStandards | ConvertFrom-Json
            try {
                Add-CIPPAzDataTableEntity @Table -Entity $StandardsBackup -Force
            } catch {
                $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
                "Could not restore Standards $ErrorMessage "
            }
        }

    }
    return $RestoreData
}


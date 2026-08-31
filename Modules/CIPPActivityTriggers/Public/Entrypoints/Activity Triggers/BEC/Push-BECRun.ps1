function Push-BECRun {
    <#
        .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $TenantFilter = $Item.TenantFilter
    $SuspectUser = $Item.UserID
    $UserName = $Item.userName

    if (!$TenantFilter -or !$SuspectUser) {
        Write-Information 'BEC: No user or tenant specified'
        return
    }
    $Table = Get-CippTable -tablename 'cachebec'

    Write-Information "Working on $UserName"
    try {
        $startDate = (Get-Date).ToUniversalTime().AddDays(-7)
        $endDate = (Get-Date).ToUniversalTime()

        # conditionalAccessStatus is 'success'/'notApplied'/'failure'; errorCode 0 is a successful
        # sign-in. Shared by every sign-in projection below.
        $SignInStatus = { if ($_.conditionalAccessStatus -in @('success', 'notApplied') -and $_.status.errorCode -eq 0) { 'Success' } else { 'Failed' } }
        # ISO 8601 so the frontend table formatter and new Date() can both parse it - Out-String
        # renders a locale string neither understands
        $SignInDate = { if ($_.createdDateTime) { ([datetime]$_.createdDateTime).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null } }

        Write-Information 'Getting audit logs'
        try {
            $auditLog = (New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-AdminAuditLogConfig').UnifiedAuditLogIngestionEnabled
            $7DaysLog = if ($auditLog -eq $false) {
                $ExtractResult = 'AuditLog is disabled. Cannot perform full analysis'
            } else {
                $sessionid = Get-Random -Minimum 10000 -Maximum 99999
                $operations = @(
                    'Remove-MailboxPermission',
                    'Add-MailboxPermission',
                    'UpdateCalendarDelegation',
                    'AddFolderPermissions'
                )
                $SearchParam = @{
                    SessionCommand = 'ReturnLargeSet'
                    Operations     = $operations
                    sessionid      = $sessionid
                    startDate      = $startDate
                    endDate        = $endDate
                }
                do {
                    $logsTenant = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Search-unifiedAuditLog' -cmdParams $SearchParam -Anchor $Username
                    Write-Information "Retrieved $($logsTenant.count) logs"
                    $logsTenant
                } while ($LogsTenant.count % 5000 -eq 0 -and $LogsTenant.count -ne 0)
                $ExtractResult = 'Successfully extracted logs from auditlog'
            }
        } catch {
            $7DaysLog = @()
            $CippAuditError = Get-CippException -Exception $_
            $ExtractResult = "Could not retrieve audit logs: $($CippAuditError.NormalizedError)"
            Write-LogMessage -API 'BECRun' -message "Failed to retrieve audit logs for $($UserName): $($CippAuditError.NormalizedError)" -tenant $TenantFilter -sev Warning -LogData $CippAuditError
        }
        Write-Information 'Getting last sign-in'
        try {
            $URI = "https://graph.microsoft.com/beta/auditLogs/signIns?`$filter=(userId eq '$SuspectUser')&`$top=1&`$orderby=createdDateTime desc"
            $LastSignIn = New-GraphGetRequest -uri $URI -tenantid $TenantFilter -noPagination $true -verbose | Select-Object @{ Name = 'CreatedDateTime'; Expression = $SignInDate },
            id,
            @{ Name = 'AppDisplayName'; Expression = { $_.resourceDisplayName } },
            @{ Name = 'Status'; Expression = $SignInStatus },
            @{ Name = 'IPAddress'; Expression = { $_.ipAddress } },
            @{ Name = 'Country'; Expression = { $_.location.countryOrRegion } },
            @{ Name = 'City'; Expression = { $_.location.city } }
        } catch {
            $LastSignIn = [PSCustomObject]@{
                AppDisplayName  = 'Unknown - could not retrieve information. No access to sign-in logs'
                CreatedDateTime = 'Unknown'
                Id              = '0'
                Status          = 'Could not retrieve additional details'
            }
        }
        Write-Information 'Getting suspect user sign-ins'
        $SuspectUserSignInsError = $null
        try {
            $URI = "https://graph.microsoft.com/beta/auditLogs/signIns?`$filter=(userId eq '$SuspectUser')&`$top=50&`$orderby=createdDateTime desc"
            $SuspectUserSignIns = @(New-GraphGetRequest -uri $URI -tenantid $TenantFilter -noPagination $true | Select-Object @{ Name = 'CreatedDateTime'; Expression = $SignInDate },
                id,
                @{ Name = 'AppDisplayName'; Expression = { $_.resourceDisplayName } },
                @{ Name = 'ClientAppUsed'; Expression = { $_.clientAppUsed } },
                @{ Name = 'Status'; Expression = $SignInStatus },
                @{ Name = 'IPAddress'; Expression = { $_.ipAddress } },
                @{ Name = 'Country'; Expression = { $_.location.countryOrRegion } },
                @{ Name = 'City'; Expression = { $_.location.city } })
        } catch {
            $SuspectUserSignIns = @()
            $CippSignInError = Get-CippException -Exception $_
            $SuspectUserSignInsError = "Could not retrieve sign-in logs: $($CippSignInError.NormalizedError)"
            Write-LogMessage -API 'BECRun' -message "Failed to retrieve sign-ins for $($UserName): $($CippSignInError.NormalizedError)" -tenant $TenantFilter -sev Warning -LogData $CippSignInError
        }
        Write-Information 'Getting user devices'
        #List all users devices
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($SuspectUser)
        $base64IdentityParam = [Convert]::ToBase64String($Bytes)
        try {
            $Devices = New-GraphGetRequest -uri "https://outlook.office365.com:443/adminapi/beta/$($TenantFilter)/mailbox('$($base64IdentityParam)')/MobileDevice/Exchange.GetMobileDeviceStatistics()/?IsEncoded=True" -Tenantid $TenantFilter -scope ExchangeOnline
        } catch {
            $Devices = $null
        }

        try {
            # for the target-mailbox heuristic below: canonical ObjectIds carry the alias, not the UPN
            $UserLocalPart = ($UserName -split '@')[0]
            $PermissionsLog = ($7DaysLog | Where-Object -Property Operations -In 'Remove-MailboxPermission', 'Add-MailboxPermission', 'UpdateCalendarDelegation', 'AddFolderPermissions' ).AuditData | ConvertFrom-Json -ErrorAction Stop | ForEach-Object {
                $perms = if ($_.Parameters) {
                    $_.Parameters | ForEach-Object { if ($_.Name -eq 'AccessRights') { $_.Value } }
                } else
                { $_.item.ParentFolder.MemberRights }
                $objectID = if ($_.ObjectID) { $_.ObjectID } else { $($_.MailboxOwnerUPN) + $_.item.ParentFolder.Path }
                # this is a tenant-wide search; flag the rows that concern the investigated mailbox
                # so the threat score can weight them above unrelated tenant churn
                $IdentityParam = if ($_.Parameters) { ($_.Parameters | Where-Object { $_.Name -eq 'Identity' }).Value }
                $TargetCandidates = @($objectID, $IdentityParam, $_.MailboxOwnerUPN) -join ' '
                [pscustomobject]@{
                    Operation      = $_.Operation
                    UserKey        = $_.UserKey
                    ObjectId       = $objectId
                    Permissions    = $perms
                    TargetsSuspect = ($TargetCandidates -like "*$UserName*" -or ($UserLocalPart -and $TargetCandidates -like "*$UserLocalPart*"))
                }
            }
        } catch {
            $PermissionsLog = @()
        }

        Write-Information 'Getting inbox rule changes'
        try {
            $RuleChangesLog = if ($auditLog -eq $false) { @() } else {
                # ponytail: separate user-scoped search - UpdateInboxRules is too high-volume for the tenant-wide query above
                $RuleSearchParam = @{
                    SessionCommand = 'ReturnLargeSet'
                    Operations     = @('New-InboxRule', 'Set-InboxRule', 'Remove-InboxRule', 'UpdateInboxRules')
                    sessionid      = (Get-Random -Minimum 10000 -Maximum 99999)
                    startDate      = $startDate
                    endDate        = $endDate
                    # Must be an array: New-ExoRequest JSON-serializes cmdParams, and a bare
                    # string binds to Search-UnifiedAuditLog's String[] UserIds as a scalar,
                    # which EXO rejects with an argument transformation error.
                    UserIds        = @($UserName)
                }
                # A search with no hits returns no AuditData at all, and piping that null into
                # ConvertFrom-Json throws - which would report every clean user as a failure.
                $RuleAuditData = (New-ExoRequest -tenantid $TenantFilter -cmdlet 'Search-UnifiedAuditLog' -cmdParams $RuleSearchParam -Anchor $UserName).AuditData
                if (-not $RuleAuditData) { @() } else {
                    $RuleAuditData | ConvertFrom-Json -ErrorAction Stop |
                        Where-Object { $_.UserId -eq $UserName -or $_.MailboxOwnerUPN -eq $UserName -or $_.ObjectId -like "*$UserName*" } | ForEach-Object {
                            $RuleName = ($_.Parameters | Where-Object { $_.Name -eq 'Name' }).Value ?? $_.ObjectId
                            [pscustomobject]@{
                                Operation  = $_.Operation
                                UserKey    = $_.UserId
                                RuleName   = $RuleName
                                Parameters = ($_.Parameters | Where-Object { $_ -and $_.Name -notin 'Identity', 'Name' } | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join '; '
                                Date       = $_.CreationTime
                                # admin-cmdlet records carry ClientIP, mailbox-sync records (UpdateInboxRules) ClientIPAddress
                                ClientIP   = $_.ClientIP ?? $_.ClientIPAddress
                            }
                        }
                }
            }
        } catch {
            $RuleChangesLog = @()
            $CippRuleError = Get-CippException -Exception $_
            Write-LogMessage -API 'BECRun' -message "Failed to retrieve inbox rule changes for $($UserName): $($CippRuleError.NormalizedError)" -tenant $TenantFilter -sev Warning -LogData $CippRuleError
        }

        Write-Information 'Getting rules'

        try {
            $RulesLog = New-ExoRequest -cmdlet 'Get-InboxRule' -tenantid $TenantFilter -cmdParams @{ Mailbox = $Username; IncludeHidden = $true } -Anchor $Username |
                Where-Object { $_.Name -ne 'Junk E-Mail Rule' -and $_.Name -notlike 'Microsoft.Exchange.OOF.*' }
        } catch {
            $CippRulesError = Get-CippException -Exception $_
            Write-LogMessage -API 'BECRun' -message "Failed to retrieve inbox rules for $($UserName): $($CippRulesError.NormalizedError)" -tenant $TenantFilter -sev Warning -LogData $CippRulesError
            $RulesLog = @()
        }

        # inbox rules carry no timestamps, so 'recent' = name-matches a 7-day audit event; Outlook-client changes (UpdateInboxRules) carry no rule name and stay unflagged
        $RecentRuleNames = @($RuleChangesLog | Where-Object { $_.Operation -in 'New-InboxRule', 'Set-InboxRule' } | ForEach-Object { ($_.RuleName -split '\\')[-1] })
        $RulesLog = @($RulesLog | Where-Object { $_ } | Select-Object *, @{ Name = 'RecentlyChanged'; Expression = { $_.Name -in $RecentRuleNames } })

        Write-Information 'Getting trusted and blocked senders'
        $SafelistError = $null
        try {
            $JunkConfig = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxJunkEmailConfiguration' -cmdParams @{ Identity = $UserName } -Anchor $UserName
            $TrustedSenders = @($JunkConfig.TrustedSendersAndDomains | Where-Object { $_ })
            $BlockedSenders = @($JunkConfig.BlockedSendersAndDomains | Where-Object { $_ })
        } catch {
            $TrustedSenders = @()
            $BlockedSenders = @()
            $CippSafelistError = Get-CippException -Exception $_
            $SafelistError = "Could not retrieve the trusted/blocked senders list: $($CippSafelistError.NormalizedError)"
            Write-LogMessage -API 'BECRun' -message "Failed to retrieve junk email configuration for $($UserName): $($CippSafelistError.NormalizedError)" -tenant $TenantFilter -sev Warning -LogData $CippSafelistError
        }

        Write-Information 'Getting safelist changes'
        try {
            $SafelistChanges = if ($auditLog -eq $false) { @() } else {
                $SafelistSearchParam = @{
                    SessionCommand = 'ReturnLargeSet'
                    Operations     = @('Set-MailboxJunkEmailConfiguration')
                    sessionid      = (Get-Random -Minimum 10000 -Maximum 99999)
                    startDate      = $startDate
                    endDate        = $endDate
                    # array for the same String[] binding reason as the rule search above
                    UserIds        = @($UserName)
                }
                $SafelistAuditData = (New-ExoRequest -tenantid $TenantFilter -cmdlet 'Search-UnifiedAuditLog' -cmdParams $SafelistSearchParam -Anchor $UserName).AuditData
                if (-not $SafelistAuditData) { @() } else {
                    @($SafelistAuditData | ConvertFrom-Json -ErrorAction Stop | ForEach-Object {
                            $TrustedValue = ($_.Parameters | Where-Object { $_.Name -eq 'TrustedSendersAndDomains' }).Value
                            $BlockedValue = ($_.Parameters | Where-Object { $_.Name -eq 'BlockedSendersAndDomains' }).Value
                            [pscustomobject]@{
                                Operation = $_.Operation
                                UserKey   = $_.UserId
                                Date      = $_.CreationTime
                                ClientIP  = $_.ClientIP ?? $_.ClientIPAddress
                                # the audit record carries the full new list, not a delta
                                Trusted   = if ($TrustedValue) { @(($TrustedValue -split ';').Trim() | Where-Object { $_ }) } else { $null }
                                Blocked   = if ($BlockedValue) { @(($BlockedValue -split ';').Trim() | Where-Object { $_ }) } else { $null }
                            }
                        })
                }
            }
        } catch {
            $SafelistChanges = @()
            $CippSafelistChangeError = Get-CippException -Exception $_
            Write-LogMessage -API 'BECRun' -message "Failed to retrieve safelist changes for $($UserName): $($CippSafelistChangeError.NormalizedError)" -tenant $TenantFilter -sev Warning -LogData $CippSafelistChangeError
        }

        Write-Information 'Getting sharing link activity'
        try {
            $SharingChanges = if ($auditLog -eq $false) { @() } else {
                $SharingSearchParam = @{
                    SessionCommand = 'ReturnLargeSet'
                    # link creation/changes only - AnonymousLinkUsed and access events are usage, not exposure changes
                    Operations     = @('SharingSet', 'SharingInvitationCreated', 'AnonymousLinkCreated', 'AnonymousLinkUpdated', 'SecureLinkCreated', 'SecureLinkUpdated', 'AddedToSecureLink', 'CompanyLinkCreated')
                    sessionid      = (Get-Random -Minimum 10000 -Maximum 99999)
                    startDate      = $startDate
                    endDate        = $endDate
                    # array for the same String[] binding reason as the rule search above
                    UserIds        = @($UserName)
                }
                $SharingAuditData = (New-ExoRequest -tenantid $TenantFilter -cmdlet 'Search-UnifiedAuditLog' -cmdParams $SharingSearchParam -Anchor $UserName).AuditData
                if (-not $SharingAuditData) { @() } else {
                    @($SharingAuditData | ConvertFrom-Json -ErrorAction Stop | ForEach-Object {
                            [pscustomobject]@{
                                Operation  = $_.Operation
                                UserKey    = $_.UserId
                                Date       = $_.CreationTime
                                Workload   = $_.Workload
                                FileName   = $_.SourceFileName
                                ItemUrl    = $_.ObjectId
                                Target     = $_.TargetUserOrGroupName
                                TargetType = $_.TargetUserOrGroupType
                                ClientIP   = $_.ClientIP ?? $_.ClientIPAddress
                            }
                        })
                }
            }
        } catch {
            $SharingChanges = @()
            $CippSharingError = Get-CippException -Exception $_
            Write-LogMessage -API 'BECRun' -message "Failed to retrieve sharing link activity for $($UserName): $($CippSharingError.NormalizedError)" -tenant $TenantFilter -sev Warning -LogData $CippSharingError
        }

        Write-Information 'Getting sent message trace'
        try {
            $MessageTraceParams = @{
                SenderAddress = $UserName
                StartDate     = $startDate.ToString('s')
                EndDate       = $endDate.ToString('s')
            }
            $SentMessagesRaw = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MessageTraceV2' -cmdParams $MessageTraceParams -Anchor $UserName)
            $SentMessages = @($SentMessagesRaw | Select-Object MessageTraceId, Status, Subject, RecipientAddress, @{ Name = 'Received'; Expression = { $_.Received.ToString('u') } }, FromIP)
        } catch {
            $SentMessagesRaw = @()
            $SentMessages = @()
            $CippTraceError = Get-CippException -Exception $_
            Write-LogMessage -API 'BECRun' -message "Failed to retrieve message trace for $($UserName): $($CippTraceError.NormalizedError)" -tenant $TenantFilter -sev Warning -LogData $CippTraceError
        }

        # Outbound mail pattern analysis. The trace returns one row per recipient, so 'messages'
        # are distinct MessageTraceIds and 'recipients' are rows - one mail BCC'd to 200 people
        # and 200 individual sends are both blasts, just along different axes.
        try {
            $RepeatSubjectMessages = 5      # same subject sent as this many separate messages
            $RepeatSubjectRecipients = 20   # or reaching this many recipients in total
            $BurstMessages = 10             # distinct messages inside one window
            $BurstRecipients = 30           # or recipients inside one window
            $BurstWindowTicks = [timespan]::FromMinutes(10).Ticks

            $RepeatedSubjects = @($SentMessagesRaw | Group-Object -Property { ([string]$_.Subject).Trim().ToLowerInvariant() } | ForEach-Object {
                    $MessageCount = @($_.Group.MessageTraceId | Select-Object -Unique).Count
                    $Times = @($_.Group.Received | Sort-Object)
                    [pscustomobject]@{
                        Subject        = if ([string]::IsNullOrWhiteSpace($_.Group[0].Subject)) { '(no subject)' } else { $_.Group[0].Subject }
                        MessageCount   = $MessageCount
                        RecipientCount = $_.Count
                        FirstSent      = if ($Times.Count -gt 0) { ([datetime]$Times[0]).ToString('u') } else { $null }
                        LastSent       = if ($Times.Count -gt 0) { ([datetime]$Times[-1]).ToString('u') } else { $null }
                        Flagged        = ($MessageCount -ge $RepeatSubjectMessages -or $_.Count -ge $RepeatSubjectRecipients)
                    }
                } | Where-Object { $_.MessageCount -ge 3 -or $_.Flagged } | Sort-Object -Property MessageCount -Descending | Select-Object -First 10)

            $Bursts = @($SentMessagesRaw | Where-Object { $_.Received } | Group-Object -Property { [long](([datetime]$_.Received).ToUniversalTime().Ticks / $BurstWindowTicks) } | ForEach-Object {
                    $MessageCount = @($_.Group.MessageTraceId | Select-Object -Unique).Count
                    if ($MessageCount -ge $BurstMessages -or $_.Count -ge $BurstRecipients) {
                        $TopSubject = ($_.Group | Group-Object -Property Subject | Sort-Object -Property Count -Descending | Select-Object -First 1).Name
                        [pscustomobject]@{
                            WindowStart    = [datetime]::new(([long]$_.Name) * $BurstWindowTicks, [System.DateTimeKind]::Utc).ToString('u')
                            WindowMinutes  = 10
                            MessageCount   = $MessageCount
                            RecipientCount = $_.Count
                            TopSubject     = $TopSubject
                        }
                    }
                } | Sort-Object -Property RecipientCount -Descending | Select-Object -First 10)

            $SentMessageAnalysis = [PSCustomObject]@{
                TotalMessages       = @($SentMessagesRaw.MessageTraceId | Select-Object -Unique).Count
                TotalRecipients     = @($SentMessagesRaw).Count
                RepeatedSubjects    = $RepeatedSubjects
                FlaggedSubjectCount = @($RepeatedSubjects | Where-Object { $_.Flagged }).Count
                Bursts              = $Bursts
                Flagged             = (@($RepeatedSubjects | Where-Object { $_.Flagged }).Count -gt 0 -or @($Bursts).Count -gt 0)
            }
        } catch {
            $SentMessageAnalysis = [PSCustomObject]@{
                TotalMessages       = @($SentMessages).Count
                TotalRecipients     = @($SentMessages).Count
                RepeatedSubjects    = @()
                FlaggedSubjectCount = 0
                Bursts              = @()
                Flagged             = $false
            }
            Write-LogMessage -API 'BECRun' -message "Failed to analyze sent message patterns for $($UserName): $($_.Exception.Message)" -tenant $TenantFilter -sev Warning
        }

        Write-Information 'Getting last 50 tenant sign-ins'
        try {
            $TenantLastSignIns = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/auditLogs/signIns?`$filter=userDisplayName ne 'On-Premises Directory Synchronization Service Account'&`$top=50&`$orderby=createdDateTime desc" -tenantid $TenantFilter -noPagination $true | Select-Object @{ Name = 'CreatedDateTime'; Expression = $SignInDate },
            id,
            @{ Name = 'AppDisplayName'; Expression = { $_.resourceDisplayName } },
            @{ Name = 'Status'; Expression = $SignInStatus },
            @{ Name = 'IPAddress'; Expression = { $_.ipAddress } },
            @{ Name = 'Country'; Expression = { $_.location.countryOrRegion } },
            @{ Name = 'City'; Expression = { $_.location.city } }, UserPrincipalName, UserDisplayName
        } catch {
            $TenantLastSignIns = @(
                [PSCustomObject]@{
                    AppDisplayName  = 'Unknown - could not retrieve information. No access to sign-in logs'
                    CreatedDateTime = 'Unknown'
                    Id              = '0'
                    Status          = 'Could not retrieve additional details'
                    Exception       = $_.Exception.Message
                }
            )
        }

        # Known-malicious application catalog shipped with CIPP; matched on appId below.
        $MaliciousAppsCatalog = try {
            @((Get-Content -Path (Join-Path $env:CIPPRootPath 'Config\MaliciousApps.json') -ErrorAction Stop | ConvertFrom-Json).applications)
        } catch {
            Write-Information "Could not load MaliciousApps.json: $($_.Exception.Message)"
            @()
        }

        $Requests = @(
            @{
                id     = 'Users'
                url    = "users?`$select=id,displayName,userPrincipalName,createdDateTime,lastPasswordChangeDateTime"
                method = 'GET'
            }
            @{
                id     = 'MFADevices'
                url    = "users/$($SuspectUser)/authentication/methods"
                method = 'GET'
            }
            @{
                id     = 'NewSPs'
                url    = "servicePrincipals?`$select=displayName,createdDateTime,appId,appDisplayName,publisher&`$filter=createdDateTime ge $($startDate.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
                method = 'GET'
            }
            @{
                id     = 'IntuneDevices'
                url    = "users/$($SuspectUser)/managedDevices"
                method = 'GET'
            }
            @{
                id     = 'SuspectUser'
                url    = "users/$($SuspectUser)?`$select=id,displayName,userPrincipalName,usageLocation,country,city"
                method = 'GET'
            }
        )
        # Look for catalog apps present in the tenant regardless of age, chunked to keep each
        # 'in' filter within Graph's operand limit.
        $CatalogAppIds = @($MaliciousAppsCatalog.appId | Where-Object { $_ })
        for ($i = 0; $i -lt $CatalogAppIds.Count; $i += 15) {
            $Chunk = $CatalogAppIds[$i..([Math]::Min($i + 14, $CatalogAppIds.Count - 1))]
            $Requests += @{
                id     = "MaliciousSPs$i"
                url    = "servicePrincipals?`$select=displayName,appId,accountEnabled,createdDateTime&`$filter=appId in ('$($Chunk -join "','")')"
                method = 'GET'
            }
        }

        Write-Information 'Getting bulk requests'
        $GraphResults = New-GraphBulkRequest -Requests $Requests -tenantid $TenantFilter -asapp $true

        $PasswordChanges = (($GraphResults | Where-Object { $_.id -eq 'Users' }).body.value | Where-Object { $_.lastPasswordChangeDateTime -ge $startDate }) ?? @()
        $NewUsers = (($GraphResults | Where-Object { $_.id -eq 'Users' }).body.value | Where-Object { $_.createdDateTime -ge $startDate }) ?? @()
        $MFADevices = ($GraphResults | Where-Object { $_.id -eq 'MFADevices' }).body.value ?? @()
        $NewSPs = ($GraphResults | Where-Object { $_.id -eq 'NewSPs' }).body.value ?? @()

        $SuspectUserDetail = ($GraphResults | Where-Object { $_.id -eq 'SuspectUser' }).body
        if ($SuspectUserDetail.error) { $SuspectUserDetail = $null }
        $UsageLocation = if ([string]::IsNullOrWhiteSpace($SuspectUserDetail.usageLocation)) { $null } else { $SuspectUserDetail.usageLocation }

        # Flag service principals added during the window that match the malicious catalog
        $NewSPs = @(foreach ($SP in @($NewSPs)) {
                $CatalogEntry = $MaliciousAppsCatalog | Where-Object { $_.appId -eq $SP.appId } | Select-Object -First 1
                $Match = if ($CatalogEntry) {
                    [PSCustomObject]@{ Name = $CatalogEntry.name; Categories = @($CatalogEntry.categories); Description = $CatalogEntry.description }
                } else { $null }
                $SP | Select-Object *, @{ Name = 'MaliciousMatch'; Expression = { $Match } }
            })

        # Catalog apps present in the tenant at all - persistence via OAuth consent survives a
        # password reset, so an old grant matters as much as a new one.
        $MaliciousSPResults = @($GraphResults | Where-Object { $_.id -like 'MaliciousSPs*' -and [int]$_.status -lt 400 } | ForEach-Object { $_.body.value } | Where-Object { $_ })
        $MaliciousSPs = @(foreach ($SP in $MaliciousSPResults) {
                $CatalogEntry = $MaliciousAppsCatalog | Where-Object { $_.appId -eq $SP.appId } | Select-Object -First 1
                [PSCustomObject]@{
                    displayName     = $SP.displayName
                    appId           = $SP.appId
                    accountEnabled  = $SP.accountEnabled
                    createdDateTime = $SP.createdDateTime
                    CatalogName     = $CatalogEntry.name
                    Categories      = @($CatalogEntry.categories)
                    Description     = $CatalogEntry.description
                }
            })

        # Intune managed devices for the suspect user — surface Graph failures instead of a silent empty list
        $IntuneResponse = $GraphResults | Where-Object { $_.id -eq 'IntuneDevices' } | Select-Object -First 1
        $IntuneDevicesError = $null
        $IntuneDevices = @()
        if (-not $IntuneResponse) {
            $IntuneDevicesError = 'Intune device query did not return a response'
        } elseif ([int]$IntuneResponse.status -ge 400) {
            # Graph proxies this call to Intune's DeviceFE service, which returns its own JSON
            # error blob as the Graph error message. Unwrap it so the report shows a readable
            # sentence instead of raw JSON, keeping the Activity ID for Microsoft support cases.
            $RawIntuneError = $IntuneResponse.body.error.message
            $IntuneDevicesError = $RawIntuneError
            if ($RawIntuneError -match '^\s*\{') {
                try {
                    $ParsedIntuneError = $RawIntuneError | ConvertFrom-Json -ErrorAction Stop
                    if (-not [string]::IsNullOrWhiteSpace($ParsedIntuneError.Message)) {
                        $IntuneDevicesError = $ParsedIntuneError.Message
                    }
                } catch {
                    # Not valid JSON after all - keep the raw message
                }
            }
            if ($IntuneDevicesError -like 'An error has occurred*') {
                $ActivityId = [regex]::Match($IntuneDevicesError, 'Activity ID: ([0-9a-fA-F-]{36})').Groups[1].Value
                $IntuneDevicesError = "Intune returned an unexpected error (HTTP $($IntuneResponse.status)). This is a failure inside the Intune service itself - usually transient, or the tenant does not have Intune provisioned. Rerun the check to retry.$(if ($ActivityId) { " Microsoft support reference (Activity ID): $ActivityId" })"
            }
            if ([string]::IsNullOrWhiteSpace($IntuneDevicesError)) {
                $IntuneDevicesError = "Intune device query failed with status $($IntuneResponse.status)"
            }
            Write-LogMessage -API 'BECRun' -message "Failed to retrieve Intune devices for $($UserName): $IntuneDevicesError" -tenant $TenantFilter -sev Warning
        } else {
            $IntuneDevicesRaw = $IntuneResponse.body.value ?? @()
            $IntuneDevices = @(
                foreach ($Device in @($IntuneDevicesRaw)) {
                    [PSCustomObject]@{
                        id                     = $Device.id
                        deviceName             = $Device.deviceName
                        operatingSystem        = $Device.operatingSystem
                        osVersion              = $Device.osVersion
                        complianceState        = $Device.complianceState
                        enrolledDateTime       = if ($Device.enrolledDateTime) { ([datetime]$Device.enrolledDateTime).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
                        lastSyncDateTime       = if ($Device.lastSyncDateTime) { ([datetime]$Device.lastSyncDateTime).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
                        deviceEnrollmentType   = $Device.deviceEnrollmentType
                        manufacturer           = $Device.manufacturer
                        model                  = $Device.model
                        serialNumber           = $Device.serialNumber
                        userPrincipalName      = $Device.userPrincipalName
                        managedDeviceOwnerType = $Device.managedDeviceOwnerType
                    }
                }
            )
        }

        # Geo-locate the client IPs behind rule changes, safelist changes and sent mail so
        # activity can be compared against the user's assigned usage location. Sign-ins carry
        # their own location from Graph. A geo failure degrades to no location, never a failed run.
        Write-Information 'Resolving IP locations'
        $ClientIpRegex = [regex]'^(?<IP>(?:\d{1,3}(?:\.\d{1,3}){3}|\[[0-9a-fA-F:]+\]|[0-9a-fA-F:]+))(?::\d+)?$'
        $GeoIPCandidates = [System.Collections.Generic.List[string]]::new()
        foreach ($Row in (@($RuleChangesLog) + @($SafelistChanges) + @($SharingChanges))) { if ($Row.ClientIP) { $GeoIPCandidates.Add([string]$Row.ClientIP) } }
        foreach ($Row in @($SentMessages)) { if ($Row.FromIP) { $GeoIPCandidates.Add([string]$Row.FromIP) } }
        $GeoMap = @{}
        if ($GeoIPCandidates.Count -gt 0) {
            try {
                $GeoMap = Get-CIPPGeoIPLocationBatch -IPs $GeoIPCandidates
            } catch {
                Write-LogMessage -API 'BECRun' -message "Failed to geo-locate activity IPs for $($UserName): $($_.Exception.Message)" -tenant $TenantFilter -sev Warning
                $GeoMap = @{}
            }
        }
        $GetGeo = {
            param($RawIP)
            if ([string]::IsNullOrWhiteSpace($RawIP)) { return $null }
            # same normalization the batch helper applies to its keys (strip :port and brackets)
            $Clean = $ClientIpRegex.Replace(([string]$RawIP).Trim(), '${IP}') -replace '[\[\]]', ''
            if ([string]::IsNullOrWhiteSpace($Clean)) { return $null }
            return $GeoMap[$Clean]
        }
        # $null when either side of the comparison is unknown - only a definite mismatch counts as foreign
        $TestForeign = {
            param($Country)
            if (-not $UsageLocation -or [string]::IsNullOrWhiteSpace($Country) -or $Country -eq 'Unknown') { return $null }
            return ($Country -ne $UsageLocation)
        }

        foreach ($Row in (@($RuleChangesLog) + @($SafelistChanges) + @($SharingChanges))) {
            $Geo = & $GetGeo $Row.ClientIP
            $Row | Add-Member -NotePropertyName 'Country' -NotePropertyValue $Geo.CountryOrRegion -Force
            $Row | Add-Member -NotePropertyName 'City' -NotePropertyValue $Geo.City -Force
            $Row | Add-Member -NotePropertyName 'ForeignLocation' -NotePropertyValue (& $TestForeign $Geo.CountryOrRegion) -Force
        }
        foreach ($Row in @($SentMessages)) {
            $Geo = & $GetGeo $Row.FromIP
            $Row | Add-Member -NotePropertyName 'Country' -NotePropertyValue $Geo.CountryOrRegion -Force
            $Row | Add-Member -NotePropertyName 'City' -NotePropertyValue $Geo.City -Force
            $Row | Add-Member -NotePropertyName 'ForeignLocation' -NotePropertyValue (& $TestForeign $Geo.CountryOrRegion) -Force
        }
        foreach ($Row in @($SuspectUserSignIns)) {
            $Row | Add-Member -NotePropertyName 'ForeignLocation' -NotePropertyValue (& $TestForeign $Row.Country) -Force
        }

        $SignInCountries = @($SuspectUserSignIns | Where-Object { $_.Country } | Group-Object -Property Country | Sort-Object -Property Count -Descending | ForEach-Object {
                [PSCustomObject]@{ Country = $_.Name; Count = $_.Count }
            })
        $LocationAnalysis = [PSCustomObject]@{
            UsageLocation              = $UsageLocation
            UserRegisteredCountry      = $SuspectUserDetail.country
            SignInCountries            = $SignInCountries
            ForeignSignInCount         = @($SuspectUserSignIns | Where-Object { $_.ForeignLocation -eq $true }).Count
            # failed foreign attempts are password-spray background noise; only a success proves access
            ForeignSuccessfulSignInCount = @($SuspectUserSignIns | Where-Object { $_.ForeignLocation -eq $true -and $_.Status -eq 'Success' }).Count
            ForeignRuleChangeCount     = @($RuleChangesLog | Where-Object { $_.ForeignLocation -eq $true }).Count
            ForeignSafelistChangeCount = @($SafelistChanges | Where-Object { $_.ForeignLocation -eq $true }).Count
            ForeignSharingChangeCount  = @($SharingChanges | Where-Object { $_.ForeignLocation -eq $true }).Count
            ForeignSentMessageCount    = @($SentMessages | Where-Object { $_.ForeignLocation -eq $true }).Count
            Note                       = if (-not $UsageLocation) { 'The user has no usage location assigned in Entra ID, so activity cannot be compared against an expected country. Countries are still listed for manual review.' } else { $null }
        }

        $Results = [PSCustomObject]@{
            AddedApps                = @($NewSPs)
            MaliciousSPs             = @($MaliciousSPs)
            SuspectUserSignIns       = @($SuspectUserSignIns)
            SuspectUserSignInsError  = $SuspectUserSignInsError
            TenantLastSignIns        = @($TenantLastSignIns)
            LastSuspectUserLogon     = @($LastSignIn)
            SuspectUserDevices       = @($Devices)
            NewRules                 = @($RulesLog)
            InboxRuleChanges         = @($RuleChangesLog)
            SentMessages             = @($SentMessages)
            SentMessageAnalysis      = $SentMessageAnalysis
            MailboxPermissionChanges = @($PermissionsLog)
            NewUsers                 = @($NewUsers)
            MFADevices               = @($MFADevices | Where-Object { $_.'@odata.type' -ne '#microsoft.graph.passwordAuthenticationMethod' })
            ChangedPasswords         = @($PasswordChanges)
            TrustedSenders           = @($TrustedSenders)
            BlockedSenders           = @($BlockedSenders)
            SafelistChanges          = @($SafelistChanges)
            SafelistError            = $SafelistError
            SharingChanges           = @($SharingChanges)
            IntuneDevices            = @($IntuneDevices)
            IntuneDevicesError       = $IntuneDevicesError
            LocationAnalysis         = $LocationAnalysis
            AnalysisWindowDays       = 7
            ExtractedAt              = (Get-Date)
            ExtractResult            = $ExtractResult
        }

        $Entity = @{
            UserId       = $SuspectUser
            Results      = [string]($Results | ConvertTo-Json -Depth 10 -Compress)
            RowKey       = $SuspectUser
            PartitionKey = 'bec'
            Status       = 'Completed'
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
        Write-LogMessage -API 'BECRun' -message "BEC Check run for $UserName" -tenant $TenantFilter -sev 'Info'
    } catch {
        $errMessage = Get-NormalizedError -message $_.Exception.Message
        $CippError = Get-CippException -Exception $_
        $results = [pscustomobject]@{'Results' = "$errMessage"; Exception = $CippError; ExtractedAt = (Get-Date) }
        Write-LogMessage -API 'BECRun' -message "Error Running BEC for $($UserName): $errMessage" -tenant $TenantFilter -sev 'Error' -LogData $CIPPError
        $Entity = @{
            UserId       = $SuspectUser
            Results      = [string]($Results | ConvertTo-Json -Depth 10 -Compress)
            RowKey       = $SuspectUser
            PartitionKey = 'bec'
            Status       = 'Error'
        }
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
    }
}

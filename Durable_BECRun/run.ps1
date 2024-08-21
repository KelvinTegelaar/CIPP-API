param($Context)
#$Context does not allow itself to be cast to a pscustomobject for some reason, so we convert
$context = $Context | ConvertTo-Json | ConvertFrom-Json
$APIName = $TriggerMetadata.FunctionName
Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
$TenantFilter = $Context.input.tenantfilter
$SuspectUser = $Context.input.userid
$UserName = $Context.input.username
Write-Information "Working on $UserName"
try {
    $startDate = (Get-Date).AddDays(-7).ToUniversalTime()
    $endDate = (Get-Date)
    Write-Information 'Getting audit logs'
    $auditLog = (New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-AdminAuditLogConfig').UnifiedAuditLogIngestionEnabled
    $7dayslog = if ($auditLog -eq $false) {
        $ExtractResult = 'AuditLog is disabled. Cannot perform full analysis'
    } else {
        $sessionid = Get-Random -Minimum 10000 -Maximum 99999
        $operations = @(
            'New-InboxRule',
            'Set-InboxRule',
            'UpdateInboxRules',
            'Remove-MailboxPermission',
            'Add-MailboxPermission',
            'UpdateCalendarDelegation',
            'AddFolderPermissions',
            'MailboxLogin',
            'UserLoggedIn'
        )
        $startDate = (Get-Date).AddDays(-7)
        $endDate = (Get-Date)
        $SearchParam = @{
            SessionCommand = 'ReturnLargeSet'
            Operations     = $operations
            sessionid      = $sessionid
            startDate      = $startDate
            endDate        = $endDate
        }
        do {
            New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Search-unifiedAuditLog' -cmdParams $SearchParam -Anchor $Username
            Write-Information "Retrieved $($logsTenant.count) logs"
            $logsTenant
        } while ($LogsTenant.count % 5000 -eq 0 -and $LogsTenant.count -ne 0)
        $ExtractResult = 'Successfully extracted logs from auditlog'
    }
    Write-Information 'Getting last sign-in'
    Try {
        $URI = "https://graph.microsoft.com/beta/auditLogs/signIns?`$filter=(userId eq '$SuspectUser')&`$top=1&`$orderby=createdDateTime desc"
        $LastSignIn = New-GraphGetRequest -uri $URI -tenantid $TenantFilter -noPagination $true -verbose | Select-Object @{ Name = 'CreatedDateTime'; Expression = { $(($_.createdDateTime | Out-String) -replace '\r\n') } },
        id,
        @{ Name = 'AppDisplayName'; Expression = { $_.resourceDisplayName } },
        @{ Name = 'Status'; Expression = { if (($_.conditionalAccessStatus -eq 'Success' -or 'Not Applied') -and $_.status.errorCode -eq 0) { 'Success' } else { 'Failed' } } },
        @{ Name = 'IPAddress'; Expression = { $_.ipAddress } }
    } catch {
        $LastSignIn = [PSCustomObject]@{
            AppDisplayName  = 'Unknown - could not retrieve information. No access to sign-in logs'
            CreatedDateTime = 'Unknown'
            Id              = '0'
            Status          = 'Could not retrieve additional details'
        }
    }
    Write-Information 'Getting user devices'
    #List all users devices
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($SuspectUser)
    $base64IdentityParam = [Convert]::ToBase64String($Bytes)
    Try {
        $Devices = New-GraphGetRequest -uri "https://outlook.office365.com:443/adminapi/beta/$($TenantFilter)/mailbox('$($base64IdentityParam)')/MobileDevice/Exchange.GetMobileDeviceStatistics()/?IsEncoded=True" -Tenantid $tenantfilter -scope ExchangeOnline
    } catch {
        $Devices = $null
    }

    try {
        $PermissionsLog = ($7dayslog | Where-Object -Property Operations -In 'Remove-MailboxPermission', 'Add-MailboxPermission', 'UpdateCalendarDelegation', 'AddFolderPermissions' ).AuditData | ConvertFrom-Json -ErrorAction Stop | ForEach-Object {
            $perms = if ($_.Parameters) {
                $_.Parameters | ForEach-Object { if ($_.Name -eq 'AccessRights') { $_.Value } }
            } else
            { $_.item.ParentFolder.MemberRights }
            $objectID = if ($_.ObjectID) { $_.ObjectID } else { $($_.MailboxOwnerUPN) + $_.item.ParentFolder.Path }
            [pscustomobject]@{
                Operation   = $_.Operation
                UserKey     = $_.UserKey
                ObjectId    = $objectId
                Permissions = $perms
            }
        }
    } catch {
        $PermissionsLog = @()
    }

    try {
        $RulesLog = @(($7dayslog | Where-Object -Property Operations -In 'New-InboxRule', 'Set-InboxRule', 'UpdateInboxRules').AuditData | ConvertFrom-Json -ErrorAction Stop) | ForEach-Object {
            Write-Information ($_ | ConvertTo-Json)
            [pscustomobject]@{
                ClientIP      = $_.ClientIP
                CreationTime  = $_.CreationTime
                UserId        = $_.UserId
                RuleName      = ($_.OperationProperties | ForEach-Object { if ($_.Name -eq 'RuleName') { $_.Value } })
                RuleCondition = ($_.OperationProperties | ForEach-Object { if ($_.Name -eq 'RuleCondition') { $_.Value } })
            }
        }
    } catch {
        $RulesLog = @()
    }

    Write-Information 'Getting last 50 logons'
    try {
        $Last50Logons = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/auditLogs/signIns?`$filter=userDisplayName ne 'On-Premises Directory Synchronization Service Account'&`$top=50&`$orderby=createdDateTime desc" -tenantid $TenantFilter -noPagination $true | Select-Object @{ Name = 'CreatedDateTime'; Expression = { $(($_.createdDateTime | Out-String) -replace '\r\n') } },
        id,
        @{ Name = 'AppDisplayName'; Expression = { $_.resourceDisplayName } },
        @{ Name = 'Status'; Expression = { if (($_.conditionalAccessStatus -eq 'Success' -or 'Not Applied') -and $_.status.errorCode -eq 0) { 'Success' } else { 'Failed' } } },
        @{ Name = 'IPAddress'; Expression = { $_.ipAddress } }, UserPrincipalName, UserDisplayName
    } catch {
        $Last50Logons = @(
            [PSCustomObject]@{
                AppDisplayName  = 'Unknown - could not retrieve information. No access to sign-in logs'
                CreatedDateTime = 'Unknown'
                Id              = '0'
                Status          = 'Could not retrieve additional details'
                Exception       = $_.Exception.Message
            }
        )
    }

    $Requests = @(
        @{
            id     = 'PasswordChanges'
            url    = "users?`$select=lastPasswordChangeDateTime,displayname,UserPrincipalName&`$filter=lastPasswordChangeDateTime ge $($startDate.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
            method = 'GET'
        }
        @{
            id     = 'NewUsers'
            url    = "users?`$select=displayname,userPrincipalName,createdDateTime?`$filter=createdDateTime ge $($startDate.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
            method = 'GET'
        }
        @{
            id     = 'MFADevices'
            url    = "users/$($SuspectUser)/authentication/methods"
            method = 'GET'
        }
        @{
            id     = 'NewSPs'
            url    = "servicePrincipals?`$select=displayName,createdDateTime,id,appDisplayName&`$filter=createdDateTime ge $($startDate.ToString('yyyy-MM-ddTHH:mm:ssZ'))"
            method = 'GET'
        }
        @{
            id     = 'Last50Logons'
            url    = "auditLogs/signIns?`$top=50&`$orderby=createdDateTime desc&`$filter=createdDateTime ge $($startDate.ToString('yyyy-MM-ddTHH:mm:ssZ')) and userDisplayName ne 'On-Premises Directory Synchronization Service Account'"
            method = 'GET'
        }
    )

    Write-Information 'Getting bulk requests'

    $GraphResults = New-GraphBulkRequest -Requests $Requests -tenantid $TenantFilter -asapp $true
    $PasswordChanges = $GraphResults | Where-Object { $_.id -eq 'PasswordChanges' } | Select-Object -ExpandProperty body
    $NewUsers = $GraphResults | Where-Object { $_.id -eq 'NewUsers' } | Select-Object -ExpandProperty body
    $MFADevices = $GraphResults | Where-Object { $_.id -eq 'MFADevices' } | Select-Object -ExpandProperty body
    $NewSPs = $GraphResults | Where-Object { $_.id -eq 'NewSPs' } | Select-Object -ExpandProperty body


    $Results = [PSCustomObject]@{
        AddedApps                = @($NewSPs)
        SuspectUserMailboxLogons = @($Last50Logons)
        LastSuspectUserLogon     = @($LastSignIn)
        SuspectUserDevices       = @($Devices)
        NewRules                 = @($RulesLog)
        MailboxPermissionChanges = @($PermissionsLog)
        NewUsers                 = @($NewUsers)
        MFADevices               = @($MFADevices)
        ChangedPasswords         = @($PasswordChanges)
        ExtractedAt              = (Get-Date).ToString('s')
        ExtractResult            = $ExtractResult
    }

} catch {
    $errMessage = Get-NormalizedError -message $_.Exception.Message
    $CippError = Get-CippException -Exception $_
    $results = [pscustomobject]@{'Results' = "$errMessage"; Exception = $CippError }
}

$Table = Get-CippTable -tablename 'cachebec'
$Table.Force = $true
Add-CIPPAzDataTableEntity @Table -Entity @{
    UserId       = $Context.input.userid
    Results      = "$($results | ConvertTo-Json -Depth 10)"
    RowKey       = $Context.input.userid
    PartitionKey = 'bec'
}

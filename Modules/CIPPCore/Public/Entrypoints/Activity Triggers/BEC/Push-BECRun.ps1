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
        $startDate = (Get-Date).AddDays(-7).ToUniversalTime()
        $endDate = (Get-Date)
        Write-Information 'Getting audit logs'
        $auditLog = (New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-AdminAuditLogConfig').UnifiedAuditLogIngestionEnabled
        $7dayslog = if ($auditLog -eq $false) {
            $ExtractResult = 'AuditLog is disabled. Cannot perform full analysis'
        } else {
            $sessionid = Get-Random -Minimum 10000 -Maximum 99999
            $operations = @(
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
                New-ExoRequest -tenantid $TenantFilter -cmdlet 'Search-unifiedAuditLog' -cmdParams $SearchParam -Anchor $Username
                Write-Information "Retrieved $($logsTenant.count) logs"
                $logsTenant
            } while ($LogsTenant.count % 5000 -eq 0 -and $LogsTenant.count -ne 0)
            $ExtractResult = 'Successfully extracted logs from auditlog'
        }
        Write-Information 'Getting last sign-in'
        try {
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
        try {
            $Devices = New-GraphGetRequest -uri "https://outlook.office365.com:443/adminapi/beta/$($TenantFilter)/mailbox('$($base64IdentityParam)')/MobileDevice/Exchange.GetMobileDeviceStatistics()/?IsEncoded=True" -Tenantid $TenantFilter -scope ExchangeOnline
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

        Write-Information 'Getting rules'

        try {
            $RulesLog = New-ExoRequest -cmdlet 'Get-InboxRule' -tenantid $TenantFilter -cmdParams @{ Mailbox = $Username; IncludeHidden = $true } -Anchor $Username |
                Where-Object { $_.Name -ne 'Junk E-Mail Rule' -and $_.Name -notlike 'Microsoft.Exchange.OOF.*' }
        } catch {
            Write-Host 'Failed to get rules: ' + $_.Exception.Message
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
        )

        Write-Information 'Getting bulk requests'
        $GraphResults = New-GraphBulkRequest -Requests $Requests -tenantid $TenantFilter -asapp $true

        $PasswordChanges = ($GraphResults | Where-Object { $_.id -eq 'Users' }).body.value | Where-Object { $_.lastPasswordChangeDateTime -ge $startDate } ?? @()
        $NewUsers = ($GraphResults | Where-Object { $_.id -eq 'Users' }).body.value | Where-Object { $_.createdDateTime -ge $startDate } ?? @()
        $MFADevices = ($GraphResults | Where-Object { $_.id -eq 'MFADevices' }).body.value ?? @()
        $NewSPs = ($GraphResults | Where-Object { $_.id -eq 'NewSPs' }).body.value ?? @()


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
        $results = [pscustomobject]@{'Results' = "$errMessage"; Exception = $CippError }
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

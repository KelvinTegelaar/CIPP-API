function Invoke-ListCalendarPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    .DESCRIPTION
        Lists calendar permissions for mailboxes in a tenant. Supports UseReportDB=true query parameter to retrieve cached data from the reporting database for significantly better performance, especially when querying AllTenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $UserID = $Request.Query.UserID
    $TenantFilter = $Request.Query.tenantFilter
    # Serve from the reporting database cache instead of live Graph. Much faster, especially for AllTenants.
    $UseReportDB = $Request.Query.UseReportDB -eq $true
    $ByUser = $Request.Query.ByUser

    try {
        # If UseReportDB is specified and no specific UserID, retrieve from report database
        if ($UseReportDB -and -not $UserID) {

            # Call the report function with proper parameters
            $ReportParams = @{
                TenantFilter = $TenantFilter
            }
            if ($ByUser -eq 'true') {
                $ReportParams.ByUser = $true
            }
            try {
                $GraphRequest = Get-CIPPCalendarPermissionReport @ReportParams
                $StatusCode = [HttpStatusCode]::OK
            } catch {
                $StatusCode = [HttpStatusCode]::InternalServerError
                $GraphRequest = $_.Exception.Message
            }

            return ([HttpResponseContext]@{
                    StatusCode = $StatusCode
                    Body       = @($GraphRequest)
                })
        }

        # Original live query logic for specific user.
        # -Select everywhere: Get-Mailbox alone is 340 properties (~15 KB) and MailboxInfo repeats
        # on every permission row.
        $GetCalParam = @{Identity = $UserID; FolderScope = 'Calendar' }
        $CalendarFolders = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxFolderStatistics' -anchor $UserID -cmdParams $GetCalParam -Select 'Name,FolderType')
        # FolderType is an internal enum and stays English whatever the mailbox language, so it
        # finds the calendar root where the folder name cannot.
        $CalendarFolder = $CalendarFolders | Where-Object { $_.FolderType -eq 'Calendar' } | Select-Object -First 1
        if (-not $CalendarFolder) { $CalendarFolder = $CalendarFolders | Select-Object -First 1 }
        $CalParam = @{Identity = "$($UserID):\$($CalendarFolder.name)" }
        $MailboxSelect = 'DisplayName,UserPrincipalName,PrimarySmtpAddress,Alias,Identity,Guid,ExchangeGuid,ExternalDirectoryObjectId,RecipientType,RecipientTypeDetails'
        $Mailbox = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -cmdParams @{Identity = $UserID } -Select $MailboxSelect
        $Permissions = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxFolderPermission' -anchor $UserID -cmdParams $CalParam -UseSystemMailbox $true -Select 'Identity,User,AccessRights,FolderName'
        # UserId is what the remove action sends back; without it Exchange only has a display name,
        # which it cannot resolve when two recipients share one.
        $Permissions = Resolve-CIPPFolderPermissionUser -TenantFilter $TenantFilter -FolderIdentity $CalParam.Identity -Permissions $Permissions
        $GraphRequest = $Permissions | Select-Object Identity, User, UserId, AccessRights, FolderName, @{ Name = 'MailboxInfo'; Expression = { $Mailbox } }

        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Calendar permissions listed for $($TenantFilter)" -sev Debug
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}

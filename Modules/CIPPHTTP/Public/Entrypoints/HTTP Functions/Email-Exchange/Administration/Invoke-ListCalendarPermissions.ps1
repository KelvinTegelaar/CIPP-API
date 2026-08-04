Function Invoke-ListCalendarPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $UserID = $Request.Query.UserID
    $TenantFilter = $Request.Query.tenantFilter
    $UseReportDB = $Request.Query.UseReportDB
    $ByUser = $Request.Query.ByUser

    try {
        # If UseReportDB is specified and no specific UserID, retrieve from report database
        if ($UseReportDB -eq 'true' -and -not $UserID) {

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

        # Original live query logic for specific user
        $GetCalParam = @{Identity = $UserID; FolderScope = 'Calendar' }
        $CalendarFolders = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxFolderStatistics' -anchor $UserID -cmdParams $GetCalParam | Select-Object -ExcludeProperty *data.type*
        $CalendarFolder = @($CalendarFolders) | Where-Object { $_.FolderType -eq 'Calendar' } | Select-Object -First 1
        if (-not $CalendarFolder) {
            $CalendarFolder = @($CalendarFolders) | Select-Object -First 1
        }
        $CalParam = @{Identity = "$($UserID):\$($CalendarFolder.name)" }
        $Mailbox = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -cmdParams @{Identity = $UserID }
        $RawPermissions = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxFolderPermission' -anchor $UserID -cmdParams $CalParam -UseSystemMailbox $true

        $ResolveCache = @{}
        $GraphRequest = foreach ($Perm in @($RawPermissions)) {
            $UserKey = [string]$Perm.User
            if (-not $ResolveCache.ContainsKey($UserKey)) {
                $ResolveCache[$UserKey] = Resolve-CIPPFolderPermissionUser -User $Perm.User -TenantFilter $TenantFilter
            }
            $Resolved = $ResolveCache[$UserKey]

            [PSCustomObject]@{
                Identity          = $Perm.Identity
                User              = $Resolved.User ?? $Perm.User
                UserEmail         = $Resolved.UserEmail
                UserId            = $Resolved.UserId
                UserAmbiguous     = [bool]$Resolved.UserAmbiguous
                CandidateEmails   = $Resolved.CandidateEmails
                AccessRights      = $Perm.AccessRights
                FolderName        = $Perm.FolderName
                MailboxInfo       = $Mailbox
            }
        }

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

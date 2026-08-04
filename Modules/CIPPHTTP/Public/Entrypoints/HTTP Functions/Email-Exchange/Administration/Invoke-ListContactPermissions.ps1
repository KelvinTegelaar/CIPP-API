Function Invoke-ListContactPermissions {
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

    try {
        $GetContactParam = @{Identity = $UserID; FolderScope = 'Contacts' }
        $ContactFolders = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxFolderStatistics' -anchor $UserID -cmdParams $GetContactParam | Select-Object -ExcludeProperty *data.type*
        $ContactFolder = @($ContactFolders) | Where-Object { $_.FolderType -eq 'Contacts' } | Select-Object -First 1
        if (-not $ContactFolder) {
            $ContactFolder = @($ContactFolders) | Select-Object -First 1
        }
        $ContactParam = @{Identity = "$($UserID):\$($ContactFolder.name)" }
        $Mailbox = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -cmdParams @{Identity = $UserID }
        $RawPermissions = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxFolderPermission' -anchor $UserID -cmdParams $ContactParam -UseSystemMailbox $true

        $ResolveCache = @{}
        $GraphRequest = foreach ($Perm in @($RawPermissions)) {
            $UserKey = [string]$Perm.User
            if (-not $ResolveCache.ContainsKey($UserKey)) {
                $ResolveCache[$UserKey] = Resolve-CIPPFolderPermissionUser -User $Perm.User -TenantFilter $TenantFilter
            }
            $Resolved = $ResolveCache[$UserKey]

            [PSCustomObject]@{
                Identity        = $Perm.Identity
                User            = $Resolved.User ?? $Perm.User
                UserEmail       = $Resolved.UserEmail
                UserId          = $Resolved.UserId
                UserAmbiguous   = [bool]$Resolved.UserAmbiguous
                CandidateEmails = $Resolved.CandidateEmails
                AccessRights    = $Perm.AccessRights
                FolderName      = $Perm.FolderName
                MailboxInfo     = $Mailbox
            }
        }

        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Contact permissions listed for $($TenantFilter)" -sev Debug
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

Function Invoke-ListContactPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    .DESCRIPTION
        Lists folder-level permissions on a user's Contacts folder in Exchange Online.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $UserID = $Request.Query.UserID
    $TenantFilter = $Request.Query.tenantFilter

    try {
        # -Select everywhere: the Contacts scope returns eight folders of ~90 properties, Get-Mailbox
        # alone is 340, and MailboxInfo repeats on every permission row.
        $GetContactParam = @{Identity = $UserID; FolderScope = 'Contacts' }
        $ContactFolders = @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxFolderStatistics' -anchor $UserID -cmdParams $GetContactParam -Select 'Name,FolderType')
        # FolderType is an internal enum and stays English whatever the mailbox language, so it finds
        # the contacts root among the seven siblings (QuickContacts, GalContacts, RecipientCache...).
        $ContactFolder = $ContactFolders | Where-Object { $_.FolderType -eq 'Contacts' } | Select-Object -First 1
        if (-not $ContactFolder) { $ContactFolder = $ContactFolders | Select-Object -First 1 }
        $ContactParam = @{Identity = "$($UserID):\$($ContactFolder.name)" }
        $MailboxSelect = 'DisplayName,UserPrincipalName,PrimarySmtpAddress,Alias,Identity,Guid,ExchangeGuid,ExternalDirectoryObjectId,RecipientType,RecipientTypeDetails'
        $Mailbox = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -cmdParams @{Identity = $UserID } -Select $MailboxSelect
        $Permissions = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxFolderPermission' -anchor $UserID -cmdParams $ContactParam -UseSystemMailbox $true -Select 'Identity,User,AccessRights,FolderName'
        # UserId is what the remove action sends back; without it Exchange only has a display name,
        # which it cannot resolve when two recipients share one.
        $Permissions = Resolve-CIPPFolderPermissionUser -TenantFilter $TenantFilter -FolderIdentity $ContactParam.Identity -Permissions $Permissions
        $GraphRequest = $Permissions | Select-Object Identity, User, UserId, AccessRights, FolderName, @{ Name = 'MailboxInfo'; Expression = { $Mailbox } }

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

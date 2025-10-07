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

    try {
        $GetCalParam = @{Identity = $UserID; FolderScope = 'Calendar' }
        $CalendarFolder = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxFolderStatistics' -anchor $UserID -cmdParams $GetCalParam | Select-Object -First 1 -ExcludeProperty *data.type*
        $CalParam = @{Identity = "$($UserID):\$($CalendarFolder.name)" }
        $Mailbox = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -cmdParams @{Identity = $UserID }
        $GraphRequest = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxFolderPermission' -anchor $UserID -cmdParams $CalParam -UseSystemMailbox $true | Select-Object Identity, User, AccessRights, FolderName, @{ Name = 'MailboxInfo'; Expression = { $Mailbox } }

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

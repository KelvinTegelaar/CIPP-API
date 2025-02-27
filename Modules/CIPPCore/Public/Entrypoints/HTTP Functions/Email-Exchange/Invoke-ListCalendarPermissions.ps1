using namespace System.Net

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
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $UserID = $Request.Query.UserID
    $TenantFilter = $Request.Query.tenantFilter

    try {
        $GetCalParam = @{Identity = $UserID; FolderScope = 'Calendar' }
        $CalendarFolder = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxFolderStatistics' -anchor $UserID -cmdParams $GetCalParam | Select-Object -First 1 -ExcludeProperty *data.type*
        $CalParam = @{Identity = "$($UserID):\$($CalendarFolder.name)" }
        $GraphRequest = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxFolderPermission' -anchor $UserID -cmdParams $CalParam -UseSystemMailbox $true | Select-Object Identity, User, AccessRights, FolderName
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Calendar permissions listed for $($TenantFilter)" -sev Debug
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })

}

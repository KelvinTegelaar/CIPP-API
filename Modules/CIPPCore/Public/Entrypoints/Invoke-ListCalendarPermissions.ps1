using namespace System.Net

Function Invoke-ListCalendarPermissions {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    $UserID = $request.Query.UserID
    $Tenantfilter = $request.Query.tenantfilter

    try {
        $GetCalParam = @{Identity = $UserID; FolderScope = 'Calendar' }
        $CalendarFolder = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-MailboxFolderStatistics' -cmdParams $GetCalParam -UseSystemMailbox $true | Select-Object -First 1
        $CalParam = @{Identity = "$($UserID):\$($CalendarFolder.name)" }
        $GraphRequest = New-ExoRequest -tenantid $Tenantfilter -cmdlet 'Get-MailboxFolderPermission' -cmdParams $CalParam -UseSystemMailbox $true | Select-Object Identity, User, AccessRights, FolderName
        Write-LogMessage -API 'List Calendar Permissions' -tenant $tenantfilter -message "Calendar permissions listed for $($tenantfilter)" -sev Debug
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

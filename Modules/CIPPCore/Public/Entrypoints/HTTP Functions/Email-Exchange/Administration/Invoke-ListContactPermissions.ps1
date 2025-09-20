using namespace System.Net

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
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $UserID = $Request.Query.UserID
    $TenantFilter = $Request.Query.tenantFilter

    try {
        $GetContactParam = @{Identity = $UserID; FolderScope = 'Contacts' }
        $ContactFolder = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxFolderStatistics' -anchor $UserID -cmdParams $GetContactParam | Select-Object -First 1 -ExcludeProperty *data.type*
        $ContactParam = @{Identity = "$($UserID):\$($ContactFolder.name)" }
        $Mailbox = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -cmdParams @{Identity = $UserID }
        $GraphRequest = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxFolderPermission' -anchor $UserID -cmdParams $ContactParam -UseSystemMailbox $true | Select-Object Identity, User, AccessRights, FolderName, @{ Name = 'MailboxInfo'; Expression = { $Mailbox } }

        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Contact permissions listed for $($TenantFilter)" -sev Debug
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

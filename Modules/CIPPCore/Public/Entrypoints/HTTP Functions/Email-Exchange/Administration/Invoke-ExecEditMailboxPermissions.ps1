using namespace System.Net

function Invoke-ExecEditMailboxPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Username = $Request.Body.userID
    $TenantFilter = $Request.Body.tenantFilter
    if ($null -eq $Username) { exit }
    $UserID = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($Username)" -tenantid $TenantFilter).id
    $Results = [System.Collections.Generic.List[string]]::new()

    $RemoveFullAccess = ($Request.Body.RemoveFullAccess).value
    foreach ($RemoveUser in $RemoveFullAccess) {
        try {
            $null = New-ExoRequest -Anchor $Username -tenantid $TenantFilter -cmdlet 'Remove-MailboxPermission' -cmdParams @{Identity = $UserID; User = $RemoveUser; AccessRights = @('FullAccess'); }
            $Results.Add("Removed $($RemoveUser) from $($Username) Shared Mailbox permissions")
            Write-LogMessage -headers $Headers -API $APIName -message "Removed $($RemoveUser) from $($Username) Shared Mailbox permission" -Sev 'Info' -tenant $TenantFilter
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Message = "Could not remove mailbox permissions for $($RemoveUser) on $($Username). Error: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
            $Results.Add($Message)
        }
    }

    $AddFullAccess = ($Request.Body.AddFullAccess).value
    foreach ($UserAutomap in $AddFullAccess) {
        try {
            $null = New-ExoRequest -Anchor $Username -tenantid $TenantFilter -cmdlet 'Add-MailboxPermission' -cmdParams @{Identity = $UserID; User = $UserAutomap; AccessRights = @('FullAccess'); AutoMapping = $true }
            $Results.Add("Granted $($UserAutomap) access to $($Username) Mailbox with AutoMapping")
            Write-LogMessage -headers $Headers -API $APIName -message "Granted $($UserAutomap) access to $($Username) Mailbox with AutoMapping" -Sev 'Info' -tenant $TenantFilter

        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Message = "Could not add mailbox permissions for $($UserAutomap) on $($Username). Error: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
            $Results.Add($Message)
        }
    }

    $AddFullAccessNoAutoMap = ($Request.Body.AddFullAccessNoAutoMap).value
    foreach ($UserNoAutomap in $AddFullAccessNoAutoMap) {
        try {
            $null = New-ExoRequest -Anchor $Username -tenantid $TenantFilter -cmdlet 'Add-MailboxPermission' -cmdParams @{Identity = $UserID; User = $UserNoAutomap; AccessRights = @('FullAccess'); AutoMapping = $false }
            $Results.Add("Granted $($UserNoAutomap) access to $($Username) Mailbox without AutoMapping")
            Write-LogMessage -headers $Headers -API $APIName -message "Granted $($UserNoAutomap) access to $($Username) Mailbox without AutoMapping" -Sev 'Info' -tenant $TenantFilter
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Message = "Could not add mailbox permissions for $($UserNoAutomap) on $($Username). Error: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
            $Results.Add($Message)
        }
    }

    $AddSendAs = ($Request.Body.AddSendAs).value

    foreach ($UserSendAs in $AddSendAs) {
        try {
            $null = New-ExoRequest -Anchor $Username -tenantid $TenantFilter -cmdlet 'Add-RecipientPermission' -cmdParams @{Identity = $UserID; Trustee = $UserSendAs; AccessRights = @('SendAs') }
            $Results.Add("Granted $($UserSendAs) access to $($Username) with Send As permissions")
            Write-LogMessage -headers $Headers -API $APIName -message "Granted $($UserSendAs) access to $($Username) with Send As permissions" -Sev 'Info' -tenant $TenantFilter
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Message = "Could not add mailbox permissions for $($UserSendAs) on $($Username). Error: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
            $Results.Add($Message)
        }
    }

    $RemoveSendAs = ($Request.Body.RemoveSendAs).value
    foreach ($UserSendAs in $RemoveSendAs) {
        try {
            $null = New-ExoRequest -Anchor $Username -tenantid $TenantFilter -cmdlet 'Remove-RecipientPermission' -cmdParams @{Identity = $UserID; Trustee = $UserSendAs; AccessRights = @('SendAs') }
            $Results.Add("Removed $($UserSendAs) from $($Username) with Send As permissions")
            Write-LogMessage -headers $Headers -API $APIName -message "Removed $($UserSendAs) from $($Username) with Send As permissions" -Sev 'Info' -tenant $TenantFilter
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Message = "Could not remove mailbox permissions for $($UserSendAs) on $($Username). Error: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
            $Results.Add($Message)
        }
    }


    $AddSendOnBehalf = ($Request.Body.AddSendOnBehalf).value
    foreach ($UserSendOnBehalf in $AddSendOnBehalf) {
        try {
            $null = New-ExoRequest -Anchor $Username -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $UserID; GrantSendonBehalfTo = @{'@odata.type' = '#Exchange.GenericHashTable'; add = $UserSendOnBehalf }; }
            $Results.Add("Granted $($UserSendOnBehalf) access to $($Username) with Send On Behalf Permissions")
            Write-LogMessage -headers $Headers -API $APIName -message "Granted $($UserSendOnBehalf) access to $($Username) with Send On Behalf Permissions" -Sev 'Info' -tenant $TenantFilter
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Message = "Could not add send on behalf permissions for $($UserSendOnBehalf) on $($Username). Error: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
            $Results.Add($Message)
        }
    }


    $RemoveSendOnBehalf = ($Request.Body.RemoveSendOnBehalf).value
    foreach ($UserSendOnBehalf in $RemoveSendOnBehalf) {
        try {
            $null = New-ExoRequest -Anchor $Username -tenantid $TenantFilter -cmdlet 'Set-Mailbox' -cmdParams @{Identity = $UserID; GrantSendonBehalfTo = @{'@odata.type' = '#Exchange.GenericHashTable'; remove = $UserSendOnBehalf }; }
            $Results.Add("Removed $($UserSendOnBehalf) from $($Username) Send on Behalf Permissions")
            Write-LogMessage -headers $Headers -API $APIName -message "Removed $($UserSendOnBehalf) from $($Username) Send on Behalf Permissions" -Sev 'Info' -tenant $TenantFilter
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Message = "Could not remove send on behalf permissions for $($UserSendOnBehalf) on $($Username). Error: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
            $Results.Add($Message)
        }
    }


    return @{
        StatusCode = [HttpStatusCode]::OK
        Body       = @{ Results = @($Results) }
    }

}

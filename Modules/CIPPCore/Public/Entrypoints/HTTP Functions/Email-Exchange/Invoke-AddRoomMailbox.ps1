using namespace System.Net

Function Invoke-AddRoomMailbox {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Room.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $User = $request.headers.'x-ms-client-principal'
    Write-LogMessage -user $User -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'


    $Results = [System.Collections.Generic.List[Object]]::new()
    $MailboxObject = $Request.body
    $AddRoomParams = [pscustomobject]@{
        Name               = $MailboxObject.username
        DisplayName        = $MailboxObject.displayName
        Room               = $true
        PrimarySMTPAddress = $MailboxObject.userPrincipalName
        ResourceCapacity   = if (![string]::IsNullOrWhiteSpace($MailboxObject.ResourceCapacity)) { $MailboxObject.ResourceCapacity } else { $null }

    }
    # Interact with query parameters or the body of the request.
    try {
        $AddRoomRequest = New-ExoRequest -tenantid $($MailboxObject.tenantid) -cmdlet 'New-Mailbox' -cmdparams $AddRoomParams
        $Results.Add("Successfully created room: $($MailboxObject.DisplayName).")
        Write-LogMessage -user $User -API $APINAME -tenant $($MailboxObject.tenantid) -message "Created room $($MailboxObject.DisplayName) with id $($AddRoomRequest.id)" -Sev 'Info'

        # Block sign-in for the mailbox
        try {
            $Request = Set-CIPPSignInState -userid $AddRoomRequest.ExternalDirectoryObjectId -TenantFilter $($MailboxObject.tenantid) -APIName $APINAME -ExecutingUser $User -AccountEnabled $false
            $Results.add("Blocked sign-in for Room mailbox; $($MailboxObject.userPrincipalName)")
        } catch {
            $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
            $Results.add("Failed to block sign-in for Room mailbox: $($MailboxObject.userPrincipalName). Error: $ErrorMessage")
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $User -API $APINAME -tenant $($MailboxObject.tenantid) -message "Failed to create room: $($MailboxObject.DisplayName). Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Results.Add("Failed to create Room mailbox $($MailboxObject.userPrincipalName). $($ErrorMessage.NormalizedError)")
    }


    $Body = [pscustomobject] @{ 'Results' = @($Results) }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}

Function Invoke-AddRoomMailbox {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Room.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Tenant = $Request.Body.tenantid

    $Results = [System.Collections.Generic.List[Object]]::new()
    $MailboxObject = $Request.Body
    $AddRoomParams = [pscustomobject]@{
        Name               = $MailboxObject.username
        DisplayName        = $MailboxObject.displayName
        Room               = $true
        PrimarySMTPAddress = $MailboxObject.userPrincipalName
        ResourceCapacity   = if (![string]::IsNullOrWhiteSpace($MailboxObject.ResourceCapacity)) { $MailboxObject.ResourceCapacity } else { $null }

    }
    # Interact with query parameters or the body of the request.
    try {
        $AddRoomRequest = New-ExoRequest -tenantid $Tenant -cmdlet 'New-Mailbox' -cmdParams $AddRoomParams
        $Results.Add("Successfully created room: $($MailboxObject.DisplayName).")
        Write-LogMessage -Headers $Headers -API $APINAME -tenant $Tenant -message "Created room $($MailboxObject.DisplayName) with id $($AddRoomRequest.id)" -Sev 'Info'

        # Block sign-in for the mailbox
        try {
            $null = Set-CIPPSignInState -userid $AddRoomRequest.ExternalDirectoryObjectId -TenantFilter $Tenant -APIName $APINAME -Headers $Headers -AccountEnabled $false
            $Results.Add("Successfully blocked sign-in for Room mailbox $($MailboxObject.userPrincipalName)")
        } catch {
            $ErrorMessage = $_.Exception.Message
            $Results.Add("Failed to block sign-in for Room mailbox: $($MailboxObject.userPrincipalName). Error: $ErrorMessage")
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to create room mailbox: $($MailboxObject.DisplayName). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message $Message -Sev 'Error' -LogData $ErrorMessage
        $Results.Add($Message)
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    $Body = [pscustomobject] @{ 'Results' = @($Results) }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

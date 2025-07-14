using namespace System.Net

Function Invoke-AddEquipmentMailbox {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Equipment.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Tenant = $Request.Body.tenantID

    $Results = [System.Collections.Generic.List[Object]]::new()
    $MailboxObject = $Request.Body

    # Create the equipment mailbox
    $NewMailboxParams = @{
        Name               = $MailboxObject.username
        DisplayName        = $MailboxObject.displayName
        Equipment          = $true
        PrimarySmtpAddress = $MailboxObject.userPrincipalName
    }

    try {
        # Create the equipment mailbox
        $AddEquipmentRequest = New-ExoRequest -tenantid $Tenant -cmdlet 'New-Mailbox' -cmdParams $NewMailboxParams
        $Results.Add("Successfully created equipment mailbox: $($MailboxObject.displayName)")

        # Block sign-in for the mailbox
        try {
            $null = Set-CIPPSignInState -userid $AddEquipmentRequest.ExternalDirectoryObjectId -TenantFilter $Tenant -APIName $APINAME -Headers $Headers -AccountEnabled $false
            $Results.Add("Successfully blocked sign-in for Equipment mailbox $($MailboxObject.userPrincipalName)")
        } catch {
            $ErrorMessage = $_.Exception.Message
            $Results.Add("Failed to block sign-in for Equipment mailbox: $($MailboxObject.userPrincipalName). Error: $ErrorMessage")
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant -message "Created equipment mailbox $($MailboxObject.displayName)" -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to create equipment mailbox: $($MailboxObject.displayName). Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant -message $Message -Sev 'Error' -LogData $ErrorMessage
        $Results.Add($Message)
        $StatusCode = [HttpStatusCode]::Forbidden
    }

    $Body = [pscustomobject]@{ 'Results' = @($Results) }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

using namespace System.Net

Function Invoke-AddSharedMailbox {
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
    Write-LogMessage -Headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $Results = [System.Collections.ArrayList]@()
    $MailboxObject = $Request.Body
    $Tenant = $MailboxObject.tenantID
    $Aliases = $MailboxObject.addedAliases -Split '\n'

    try {

        $Email = "$($MailboxObject.username)@$($MailboxObject.domain)"
        $BodyToShip = [pscustomobject] @{
            displayName        = $MailboxObject.displayName
            name               = $MailboxObject.username
            primarySMTPAddress = $Email
            Shared             = $true
        }
        $AddSharedRequest = New-ExoRequest -tenantid $Tenant -cmdlet 'New-Mailbox' -cmdParams $BodyToShip
        $Body = $Results.Add("Successfully created shared mailbox: $Email.")
        Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message "Created shared mailbox $($MailboxObject.displayName) with email $Email" -Sev 'Info'

        # Block sign-in for the mailbox
        try {
            $null = Set-CIPPSignInState -userid $AddSharedRequest.ExternalDirectoryObjectId -TenantFilter $Tenant -APIName $APIName -Headers $Headers -AccountEnabled $false
            $Body = $Results.Add("Blocked sign-in for shared mailbox $Email")
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Message = "Failed to block sign-in for shared mailbox $Email. Error: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message $Message -Sev 'Error' -LogData $ErrorMessage
            $Body = $Results.Add($Message)
        }

        # Add aliases to the mailbox if any are provided
        if ($Aliases) {
            try {
                Start-Sleep 3 # Sleep since there is apparently a race condition with the mailbox creation if we don't delay for a lil bit
                $AliasBodyToShip = [pscustomobject] @{
                    Identity       = $AddSharedRequest.Guid
                    EmailAddresses = @{'@odata.type' = '#Exchange.GenericHashTable'; Add = $Aliases }
                }
                $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-Mailbox' -cmdParams $AliasBodyToShip -UseSystemMailbox $true
                $Message = "Added aliases to $Email : $($Aliases -join ',')"
                Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message $Message -Sev 'Info'
                $Body = $Results.Add($Message)

            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $Message = "Failed to add aliases to $Email : $($ErrorMessage.NormalizedError)"
                Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message $Message -Sev 'Error' -LogData $ErrorMessage
                $Body = $Results.Add($Message)
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to create shared mailbox. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message $Message -Sev 'Error' -LogData $ErrorMessage
        $Body = $Results.Add($Message)
        $StatusCode = [HttpStatusCode]::Forbidden
    }


    $Body = [pscustomobject] @{ Results = @($Results) }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })

}

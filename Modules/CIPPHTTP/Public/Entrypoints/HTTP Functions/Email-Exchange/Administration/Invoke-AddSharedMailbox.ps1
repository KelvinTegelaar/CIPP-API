function Invoke-AddSharedMailbox {
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


    $Results = [System.Collections.Generic.List[string]]::new()
    $MailboxObject = $Request.Body
    $Tenant = $MailboxObject.tenantID
    $Aliases = $MailboxObject.addedAliases -split '\n'

    try {

        $Email = "$($MailboxObject.username)@$($MailboxObject.domain)"
        $BodyToShip = [pscustomobject] @{
            displayName        = $MailboxObject.displayName
            name               = $MailboxObject.username
            primarySMTPAddress = $Email
            Shared             = $true
        }
        $AddSharedRequest = New-ExoRequest -tenantid $Tenant -cmdlet 'New-Mailbox' -cmdParams $BodyToShip
        $Results.Add("Successfully created shared mailbox: $Email.")
        Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message "Created shared mailbox $($MailboxObject.displayName) with email $Email" -Sev 'Info'

        # Block sign-in for the mailbox
        try {
            $null = Set-CIPPSignInState -userid $AddSharedRequest.ExternalDirectoryObjectId -TenantFilter $Tenant -APIName $APIName -Headers $Headers -AccountEnabled $false
            $Results.Add("Blocked sign-in for shared mailbox $Email")
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            $Message = "Failed to block sign-in for shared mailbox $Email Error: $($ErrorMessage.NormalizedError)"
            Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message $Message -Sev 'Error' -LogData $ErrorMessage
            $Results.Add($Message)
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
                $Results.Add($Message)

            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                $Message = "Failed to add aliases to $Email : $($ErrorMessage.NormalizedError)"
                Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message $Message -Sev 'Error' -LogData $ErrorMessage
                $Results.Add($Message)
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to create shared mailbox. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $Tenant -message $Message -Sev 'Error' -LogData $ErrorMessage
        $Results.Add($Message)
        $StatusCode = [HttpStatusCode]::Forbidden
    }


    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = @($Results) }
        })

}

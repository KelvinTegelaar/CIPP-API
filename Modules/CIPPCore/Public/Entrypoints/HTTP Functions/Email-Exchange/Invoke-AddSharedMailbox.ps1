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

    $APIName = $TriggerMetadata.FunctionName
    $User = $request.headers.'x-ms-client-principal'

    Write-LogMessage -user $User -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'

    $Results = [System.Collections.ArrayList]@()
    $MailboxObject = $Request.body
    $Tenant = $MailboxObject.tenantid
    $Aliases = $MailboxObject.addedAliases -Split '\n'

    try {

        $Email = "$($MailboxObject.username)@$($MailboxObject.domain)"
        $BodyToShip = [pscustomobject] @{
            'displayName'        = $MailboxObject.Displayname
            'name'               = $MailboxObject.username
            'primarySMTPAddress' = $Email
            Shared               = $true
        }
        $AddSharedRequest = New-ExoRequest -tenantid $Tenant -cmdlet 'New-Mailbox' -cmdparams $BodyToShip
        $Body = $Results.add("Successfully created shared mailbox: $Email.")
        Write-LogMessage -user $User -API $APINAME -tenant $Tenant -message "Created shared mailbox $($MailboxObject.displayname) with email $Email" -Sev 'Info'

        # Block sign-in for the mailbox
        try {
            $null = Set-CIPPSignInState -userid $AddSharedRequest.ExternalDirectoryObjectId -TenantFilter $Tenant -APIName $APINAME -ExecutingUser $User -AccountEnabled $false
            $Body = $Results.add("Blocked sign-in for shared mailbox $Email")
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -user $User -API $APINAME -tenant $Tenant -message "Failed to block sign-in for shared mailbox $Email. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
            $Body = $Results.add("Failed to block sign-in for shared mailbox $Email. Error: $($ErrorMessage.NormalizedError)")
        }

        # Add aliases to the mailbox if any are provided
        if ($Aliases) {
            try {
                Start-Sleep 3 # Sleep since there is apparently a race condition with the mailbox creation if we don't delay for a lil bit
                $AliasBodyToShip = [pscustomobject] @{
                    'Identity'       = $AddSharedRequest.Guid
                    'EmailAddresses' = @{'@odata.type' = '#Exchange.GenericHashTable'; Add = $Aliases }
                }
                $null = New-ExoRequest -tenantid $Tenant -cmdlet 'Set-Mailbox' -cmdparams $AliasBodyToShip -UseSystemMailbox $true
                Write-LogMessage -user $User -API $APINAME -tenant $Tenant -message "Added aliases to $Email : $($Aliases -join ',')" -Sev 'Info'
                $Body = $results.add("Added Aliases to $Email : $($Aliases -join ',')")

            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -user $User -API $APINAME -tenant $Tenant -message "Failed to add aliases to $Email : $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
                $Body = $results.add("ERROR: Failed to add aliases to $Email : $($ErrorMessage.NormalizedError)")
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $User -API $APINAME -tenant $Tenant -message "Failed to create shared mailbox. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = $Results.add("Failed to create Shared Mailbox. $($ErrorMessage.NormalizedError)")
        $StatusCode = [HttpStatusCode]::Forbidden
    }


    $Body = [pscustomobject] @{ 'Results' = @($results) }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })

}

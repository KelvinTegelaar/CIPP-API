using namespace System.Net

Function Invoke-AddSharedMailbox {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    $User = $request.headers.'x-ms-client-principal'

    Write-LogMessage -user $User -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $Results = [System.Collections.ArrayList]@()
    $groupobj = $Request.body
    $Aliases = $groupobj.addedAliases -Split '\n'

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    try {

        $Email = "$($groupobj.username)@$($groupobj.domain)"
        $BodyToship = [pscustomobject] @{
            'displayName'        = $groupobj.Displayname
            'name'               = $groupobj.username
            'primarySMTPAddress' = $Email
            Shared               = $true
        }
        $AddSharedRequest = New-ExoRequest -tenantid $groupobj.tenantid -cmdlet 'New-Mailbox' -cmdparams $BodyToship
        $Body = $Results.add("Successfully created shared mailbox: $Email.")
        Write-LogMessage -user $User -API $APINAME -tenant $($groupobj.tenantid) -message "Created shared mailbox $($groupobj.displayname) with email $Email" -Sev 'Info'

    } catch {
        Write-LogMessage -user $User -API $APINAME -tenant $($groupobj.tenantid) -message "Failed to create shared mailbox. Error: $($_.Exception.Message)" -Sev 'Error'
        $Body = $Results.add("Failed to create Shared Mailbox. $($_.Exception.Message)")

    }

    try {
        if ($Aliases) {
            
            Start-Sleep 3 # Sleep since there is apparently a race condition with the mailbox creation if we don't delay for a lil bit
            $AliasBodyToShip = [pscustomobject] @{
                'Identity'       = $AddSharedRequest.Guid
                'EmailAddresses' = @{'@odata.type' = '#Exchange.GenericHashTable'; Add = $Aliases }
            }
            $AliasBodyToShip
            New-ExoRequest -tenantid $groupobj.tenantid -cmdlet 'Set-Mailbox' -cmdparams $AliasBodyToShip -UseSystemMailbox $true
            Write-LogMessage -user $User -API $APINAME -tenant $($groupobj.tenantid) -message "Added aliases to $Email : $($Aliases -join ',')" -Sev 'Info'
            $Body = $results.add("Added Aliases to $Email : $($Aliases -join ',')")
        }
    } catch {
        Write-LogMessage -user $User -API $APINAME -tenant $($groupobj.tenantid) -message "Failed to add aliases to $Email : $($_.Exception.Message)" -Sev 'Error'
        $Body = $results.add("ERROR: Failed to add aliases to $Email : $($_.Exception.Message)")
    }

    $Body = [pscustomobject] @{ 'Results' = @($results) }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}

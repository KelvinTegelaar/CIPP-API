using namespace System.Net

Function Invoke-AddSharedMailbox {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'

    $groupobj = $Request.body

    # Write to the Azure Functions log stream.
    Write-Host 'PowerShell HTTP trigger function processed a request.'
    try {

        $email = "$($groupobj.username)@$($groupobj.domain)"
        $BodyToship = [pscustomobject] @{
            'displayName'        = $groupobj.Displayname
            'name'               = $groupobj.username
            'primarySMTPAddress' = $email
            Shared               = $true

        }
        New-ExoRequest -tenantid $Request.body.tenantid -cmdlet 'New-Mailbox' -cmdparams $BodyToship

        $body = [pscustomobject]@{'Results' = 'Successfully created shared mailbox.' }
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($groupobj.tenantid) -message "Created group $($groupobj.displayname) with id $($GraphRequest.id) for " -Sev 'Info'

    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -tenant $($groupobj.tenantid) -message "Group creation API failed. $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Failed to create Shared Mailbox. $($_.Exception.Message)" }

    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}

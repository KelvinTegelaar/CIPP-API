using namespace System.Net

Function Invoke-AddTeam {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Teams.Group.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $userobj = $Request.body



    $Owners = ($userobj.owner)
    try {
        if ($null -eq $Owners) {
            throw "You have to add at least one owner to the team"
        }
        $Owners = $Owners | ForEach-Object {
            $OwnerID = "https://graph.microsoft.com/beta/users('$($_)')"
            @{
                '@odata.type'     = '#microsoft.graph.aadUserConversationMember'
                'roles'           = @('owner')
                'user@odata.bind' = $OwnerID
            }
        }

        $TeamsSettings = [PSCustomObject]@{
            'template@odata.bind' = "https://graph.microsoft.com/v1.0/teamsTemplates('standard')"
            'visibility'          = $userobj.visibility
            'displayName'         = $userobj.displayname
            'description'         = $userobj.description
            'members'             = @($owners)

        } | ConvertTo-Json -Depth 10

        Write-Host $TeamsSettings
        New-GraphPostRequest -AsApp $true -uri 'https://graph.microsoft.com/beta/teams' -tenantid $Userobj.tenantid -type POST -body $TeamsSettings -verbose
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $($userobj.tenantid) -message "Added Team $($userobj.displayname)" -Sev 'Info'
        $body = [pscustomobject]@{'Results' = 'Success. Team has been added' }

    } catch {
        Write-LogMessage -headers $Request.Headers -API $APINAME -tenant $($userobj.tenantid) -message "Adding Team failed. Error: $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Failed. Error message: $($_.Exception.Message)" }
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })

}

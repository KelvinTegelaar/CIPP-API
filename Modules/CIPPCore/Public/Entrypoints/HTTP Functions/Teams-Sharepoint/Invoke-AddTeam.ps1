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


    # Interact with the body of the request
    $TeamObj = $Request.Body
    $TenantID = $TeamObj.tenantid

    $Owners = ($TeamObj.owner)
    try {
        if ($null -eq $Owners) {
            throw 'You have to add at least one owner to the team'
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
            'visibility'          = $TeamObj.visibility
            'displayName'         = $TeamObj.displayName
            'description'         = $TeamObj.description
            'members'             = @($Owners)

        } | ConvertTo-Json -Depth 10
        # Write-Host $TeamsSettings

        $null = New-GraphPostRequest -AsApp $true -uri 'https://graph.microsoft.com/beta/teams' -tenantid $TenantID -type POST -body $TeamsSettings -Verbose
        $Message = "Successfully created Team: '$($TeamObj.displayName)'"
        Write-LogMessage -headers $Headers -API $APINAME -tenant $TenantID -message $Message -Sev Info
        $StatusCode = [HttpStatusCode]::OK

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to create Team: '$($TeamObj.displayName)'. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APINAME -tenant $TenantID -message $Message -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }


    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Message }
        })

}

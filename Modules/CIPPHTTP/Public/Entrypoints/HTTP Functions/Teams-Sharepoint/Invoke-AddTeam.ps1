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
    $MailNickname = if ($TeamObj.mailNickname) { ([string]$TeamObj.mailNickname).Trim() } else { $null }

    $Owners = ($TeamObj.owner)
    try {
        if ($null -eq $Owners) {
            throw 'You have to add at least one owner to the team'
        }

        if ($MailNickname) {
            # Graph does not accept mailNickname on POST /teams, so create the Microsoft 365 group with the
            # requested alias first and then convert that group into a team.
            if ($MailNickname -notmatch '^[A-Za-z0-9._-]+$') {
                throw 'Mail nickname may only contain letters, numbers, dots, dashes and underscores'
            }

            $OwnerBindings = [System.Collections.Generic.List[string]]::new()
            foreach ($Owner in $Owners) {
                $OwnerBindings.Add("https://graph.microsoft.com/v1.0/users/$Owner")
            }

            $GroupBody = [PSCustomObject]@{
                'displayName'        = $TeamObj.displayName
                'description'        = $TeamObj.description
                'mailNickname'       = $MailNickname
                'mailEnabled'        = $true
                'securityEnabled'    = $false
                'groupTypes'         = @('Unified')
                'visibility'         = if ($TeamObj.visibility -eq 'public') { 'Public' } else { 'Private' }
                'owners@odata.bind'  = @($OwnerBindings)
                'members@odata.bind' = @($OwnerBindings)
            } | ConvertTo-Json -Depth 10

            $Group = New-GraphPostRequest -AsApp $true -uri 'https://graph.microsoft.com/beta/groups' -tenantid $TenantID -type POST -body $GroupBody
            Write-LogMessage -headers $Headers -API $APINAME -tenant $TenantID -message "Created Microsoft 365 group '$($TeamObj.displayName)' with mail nickname '$MailNickname' (id: $($Group.id))" -Sev Info

            $TeamsSettings = [PSCustomObject]@{
                'template@odata.bind' = "https://graph.microsoft.com/v1.0/teamsTemplates('standard')"
                'group@odata.bind'    = "https://graph.microsoft.com/v1.0/groups('$($Group.id)')"
            } | ConvertTo-Json -Depth 10

            # Graph recommends retrying up to three times with a 10 second delay, as a freshly created group
            # may not have replicated yet and the team creation then fails with a 404.
            $Attempt = 0
            $MaxAttempts = 3
            $TeamCreated = $false
            do {
                $Attempt++
                try {
                    $null = New-GraphPostRequest -AsApp $true -uri 'https://graph.microsoft.com/beta/teams' -tenantid $TenantID -type POST -body $TeamsSettings
                    $TeamCreated = $true
                } catch {
                    $Is404 = $_.Exception.Message -match '404|Not Found'
                    if ($Is404 -and $Attempt -lt $MaxAttempts) {
                        Write-Information "Team creation for group $($Group.id) returned 404 on attempt $Attempt, retrying in 10 seconds"
                        Start-Sleep -Seconds 10
                    } else {
                        throw
                    }
                }
            } until ($TeamCreated -or $Attempt -ge $MaxAttempts)
        } else {
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

            $null = New-GraphPostRequest -AsApp $true -uri 'https://graph.microsoft.com/beta/teams' -tenantid $TenantID -type POST -body $TeamsSettings -Verbose
        }

        $Message = "Successfully created Team: '$($TeamObj.displayName)'$(if ($MailNickname) { " with mail nickname '$MailNickname'" })"
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

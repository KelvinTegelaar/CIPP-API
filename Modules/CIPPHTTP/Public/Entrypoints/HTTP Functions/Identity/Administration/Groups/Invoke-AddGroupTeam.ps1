function Invoke-AddGroupTeam {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.Group.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Body.TenantFilter
    $GroupId = $Request.Body.GroupId

    $Results = [System.Collections.Generic.List[string]]@()

    try {
        # Default team settings - can be customized via request body
        $TeamSettings = if ($Request.Body.TeamSettings) {
            $Request.Body.TeamSettings
        } else {
            @{
                memberSettings    = @{
                    allowCreatePrivateChannels = $true
                    allowCreateUpdateChannels  = $true
                }
                messagingSettings = @{
                    allowUserEditMessages   = $true
                    allowUserDeleteMessages = $true
                }
                funSettings       = @{
                    allowGiphy         = $true
                    giphyContentRating = 'strict'
                }
            }
        }

        # Create team from group using PUT request
        $GraphParams = @{
            uri      = "https://graph.microsoft.com/beta/groups/$GroupId/team"
            tenantid = $TenantFilter
            type     = 'PUT'
            body     = ($TeamSettings | ConvertTo-Json -Depth 10)
            AsApp    = $true
        }
        $null = New-GraphPOSTRequest @GraphParams

        $Results.Add("Successfully created team from group $GroupId")
        Write-LogMessage -API $APIName -tenant $TenantFilter -message "Created team from group $GroupId" -Sev 'Info'
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $RawMessage = $_.Exception.Message

        # Determine if this is a likely replication delay 404 (exclude owner/membership related 404s)
        $Is404 = ($RawMessage -match '404|Not Found' -or $ErrorMessage.NormalizedError -match '404|Not Found')
        $IsOwnerRelated = ($RawMessage -match 'owner' -or $ErrorMessage.NormalizedError -match 'owner')
        $IsMembershipRelated = ($RawMessage -match 'member' -or $ErrorMessage.NormalizedError -match 'member')

        $IsReplicationDelay = $Is404 -and -not ($IsOwnerRelated -or $IsMembershipRelated)

        if ($IsReplicationDelay) {
            $Results.Add('Failed to create team: The group may have been created too recently. If it was created less than 15 minutes ago, wait and retry. Groups need time to fully replicate before a team can be created.')
            Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to create team from group $GroupId - probable replication delay (404). Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        } else {
            $Results.Add("Failed to create team: $($ErrorMessage.NormalizedError)")
            Write-LogMessage -API $APIName -tenant $TenantFilter -message "Failed to create team from group $GroupId. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        }
    }

    $Body = @{
        Results = @($Results)
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}

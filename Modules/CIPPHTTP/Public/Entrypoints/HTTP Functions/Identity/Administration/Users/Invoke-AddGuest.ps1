function Invoke-AddGuest {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    $TenantFilter = $Request.Body.tenantFilter
    $DisplayName = -not [string]::IsNullOrWhiteSpace($Request.Body.displayName) ? $Request.Body.displayName : $null
    $EmailAddress = -not [string]::IsNullOrWhiteSpace($Request.Body.mail) ? $Request.Body.mail : $null
    $Message = -not [string]::IsNullOrWhiteSpace($Request.Body.message) ? $Request.Body.message : $null
    $RedirectURL = -not [string]::IsNullOrWhiteSpace($Request.Body.redirectUri) ? $Request.Body.redirectUri : 'https://myapps.microsoft.com'
    $SendInvite = [System.Convert]::ToBoolean($Request.Body.sendInvite) ?? $true

    Write-Information -MessageData "Received request to add guest with email $EmailAddress to tenant filter $TenantFilter with display name $DisplayName. SendInvite is set to $SendInvite. Redirect URL is $RedirectURL. Message is $Message"

    try {
        $BodyToShip = [pscustomobject] @{
            invitedUserDisplayName  = $DisplayName
            invitedUserEmailAddress = $EmailAddress
            inviteRedirectUrl       = $RedirectURL
            sendInvitationMessage   = $SendInvite
        }

        if (-not [string]::IsNullOrWhiteSpace($Message)) {
            $BodyToShip | Add-Member -MemberType NoteProperty -Name 'invitedUserMessageInfo' -Value ([pscustomobject]@{
                    customizedMessageBody = $Message
                })
        }

        $BodyToShipJson = ConvertTo-Json -Depth 5 -InputObject $BodyToShip
        $null = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/invitations' -tenantid $TenantFilter -type POST -body $BodyToShipJson
        if ($SendInvite -eq $true) {
            $Result = "Invited Guest $($DisplayName) with Email Invite"
        } else {
            $Result = "Invited Guest $($DisplayName) with no Email Invite"
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to Invite Guest. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ 'Results' = @($Result) }
        })

}

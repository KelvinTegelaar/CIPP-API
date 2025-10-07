Function Invoke-AddGuest {
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
    $UserObject = $Request.Body

    try {
        if ($UserObject.RedirectURL) {
            $BodyToShip = [pscustomobject] @{
                'InvitedUserDisplayName'  = $UserObject.DisplayName
                'InvitedUserEmailAddress' = $($UserObject.mail)
                'inviteRedirectUrl'       = $($UserObject.RedirectURL)
                'sendInvitationMessage'   = [bool]$UserObject.SendInvite
            }
        } else {
            $BodyToShip = [pscustomobject] @{
                'InvitedUserDisplayName'  = $UserObject.DisplayName
                'InvitedUserEmailAddress' = $($UserObject.mail)
                'sendInvitationMessage'   = [bool]$UserObject.SendInvite
                'inviteRedirectUrl'       = 'https://myapps.microsoft.com'
            }
        }
        $bodyToShip = ConvertTo-Json -Depth 10 -InputObject $BodyToShip -Compress
        $null = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/invitations' -tenantid $TenantFilter -type POST -body $BodyToShip -Verbose
        if ($UserObject.SendInvite -eq $true) {
            $Result = "Invited Guest $($UserObject.DisplayName) with Email Invite"
            Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev 'Info'
        } else {
            $Result = "Invited Guest $($UserObject.DisplayName) with no Email Invite"
            Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev 'Info'
        }
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

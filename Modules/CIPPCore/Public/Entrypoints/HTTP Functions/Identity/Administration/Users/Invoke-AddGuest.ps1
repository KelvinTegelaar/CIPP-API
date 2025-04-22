using namespace System.Net

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
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $TenantFilter = $Request.Body.tenantFilter

    $Results = [System.Collections.ArrayList]@()
    $UserObject = $Request.Body
    try {
        if ($UserObject.RedirectURL) {
            $BodyToship = [pscustomobject] @{
                'InvitedUserDisplayName'  = $UserObject.DisplayName
                'InvitedUserEmailAddress' = $($UserObject.mail)
                'inviteRedirectUrl'       = $($UserObject.RedirectURL)
                'sendInvitationMessage'   = [bool]$UserObject.SendInvite
            }
        } else {
            $BodyToship = [pscustomobject] @{
                'InvitedUserDisplayName'  = $UserObject.DisplayName
                'InvitedUserEmailAddress' = $($UserObject.mail)
                'sendInvitationMessage'   = [bool]$UserObject.SendInvite
                'inviteRedirectUrl'       = 'https://myapps.microsoft.com'
            }
        }
        $bodyToShip = ConvertTo-Json -Depth 10 -InputObject $BodyToship -Compress
        $null = New-GraphPostRequest -uri 'https://graph.microsoft.com/beta/invitations' -tenantid $TenantFilter -type POST -body $BodyToship -verbose
        if ($UserObject.SendInvite -eq $true) {
            $Results.Add('Invited Guest. Invite Email sent')
            Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Invited Guest $($UserObject.DisplayName) with Email Invite " -Sev 'Info'
        } else {
            $Results.Add('Invited Guest. No Invite Email was sent')
            Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message "Invited Guest $($UserObject.DisplayName) with no Email Invite " -Sev 'Info'
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to Invite Guest. $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $($TenantFilter) -message $Result -Sev 'Error' -LogData $ErrorMessage
        $Results.Add($Result)
        $StatusCode = [HttpStatusCode]::BadRequest
    }

    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = @($Results) }
        })

}

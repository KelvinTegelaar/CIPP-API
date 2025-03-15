using namespace System.Net
Function Invoke-ExecMailTest {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Core.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        switch ($Request.Query.Action) {
            'CheckConfig' {
                $GraphToken = Get-GraphToken -returnRefresh $true -SkipCache $true
                $AccessTokenDetails = Read-JwtAccessDetails -Token $GraphToken.access_token
                $Me = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/me?$select=displayName,userPrincipalName,proxyAddresses' -NoAuthCheck $true
                if ($AccessTokenDetails.Scope -contains 'Mail.Read') {
                    $Message = 'Mail.Read - Delegated was found in the token scope.'
                    $HasMailRead = $true
                } else {
                    $Message = 'Please add Mail.Read - Delegated to the API permissions for CIPP-SAM.'
                    $HasMailRead = $false
                }

                if ($Me.proxyAddresses) {
                    $Emails = $Me.proxyAddresses | Select-Object @{n = 'Address'; exp = { ($_ -split ':')[1] } }, @{n = 'IsPrimary'; exp = { $_ -cmatch 'SMTP' } }
                } else {
                    $Emails = @(@{ Address = $Me.userPrincipalName; IsPrimary = $true })
                }

                $Body = [PSCustomObject]@{
                    Message       = $Message
                    HasMailRead   = $HasMailRead
                    MailUser      = $Me.displayName
                    MailAddresses = @($Emails)
                }
            }
            default {
                $Messages = New-GraphGetRequest -uri "https://graph.microsoft.com/beta/me/mailFolders/Inbox/messages?`$select=receivedDateTime,subject,sender,internetMessageHeaders,webLink" -NoAuthCheck $true
                $Results = foreach ($Message in $Messages) {
                    if ($Message.receivedDateTime) {
                        $AuthResult = ($Message.internetMessageHeaders | Where-Object -Property name -EQ 'Authentication-Results').value
                        $AuthResult = $AuthResult -split ';\s*'
                        $AuthResult = $AuthResult | ForEach-Object {
                            if ($_ -match '^(?<Name>.+?)=\s*(?<Status>.+?)\s(?<Info>.+)$') {
                                [PSCustomObject]@{
                                    Name   = $Matches.Name
                                    Status = $Matches.Status
                                    Info   = $Matches.Info
                                }
                            }
                        }
                        [PSCustomObject]@{
                            Received   = $Message.receivedDateTime
                            Subject    = $Message.subject
                            Sender     = $Message.sender.emailAddress.name
                            From       = $Message.sender.emailAddress.address
                            Link       = $Message.webLink
                            Headers    = $Message.internetMessageHeaders
                            AuthResult = $AuthResult
                        }
                    }
                }
                $Body = [PSCustomObject]@{
                    Results  = @($Results)
                    Metadata = [PSCustomObject]@{
                        Count = ($Results | Measure-Object).Count
                    }
                }
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::BadRequest
        $Body = [PSCustomObject]@{
            Results = @($ErrorMessage)
        }
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}

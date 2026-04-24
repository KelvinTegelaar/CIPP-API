function Invoke-ListUserTrustedBlockedSenders {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    $TenantFilter = $Request.Query.tenantFilter
    $UserID = $Request.Query.UserID
    $UserPrincipalName = $Request.Query.userPrincipalName

    try {
        $Config = New-ExoRequest -Anchor $UserID -tenantid $TenantFilter -cmdlet 'Get-MailboxJunkEmailConfiguration' -cmdParams @{Identity = $UserID }

        $Result = [System.Collections.Generic.List[PSObject]]::new()
        $Properties = @(
            @{ Name = 'TrustedSendersAndDomains'; FriendlyName = 'Trusted Sender/Domain' },
            @{ Name = 'BlockedSendersAndDomains'; FriendlyName = 'Blocked Sender/Domain' }
        )

        foreach ($Prop in $Properties) {
            if ($Config.$($Prop.Name)) {
                foreach ($Value in $Config.$($Prop.Name)) {
                    if ($Value) {
                        $null = $Result.Add([PSCustomObject]@{
                                UserPrincipalName = $UserPrincipalName
                                UserID            = $UserID
                                Type              = $Prop.FriendlyName
                                TypeProperty      = $Prop.Name
                                Value             = $Value
                            })
                    }
                }
            }
        }

        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to retrieve junk email configuration for $UserID : Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -tenant $TenantFilter -API $APIName -message $Result -Sev Error -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Result)
        })
}

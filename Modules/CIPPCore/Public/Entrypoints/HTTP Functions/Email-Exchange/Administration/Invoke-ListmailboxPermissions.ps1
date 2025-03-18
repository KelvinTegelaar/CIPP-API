using namespace System.Net

Function Invoke-ListmailboxPermissions {
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
    Write-LogMessage -headers $Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $UserID = $Request.Query.userId

    try {
        $Requests = @(
            @{
                CmdletInput = @{
                    CmdletName = 'Get-Mailbox'
                    Parameters = @{ Identity = $UserID }
                }
            }
            @{
                CmdletInput = @{
                    CmdletName = 'Get-MailboxPermission'
                    Parameters = @{ Identity = $UserID }
                }
            }
            @{
                CmdletInput = @{
                    CmdletName = 'Get-RecipientPermission'
                    Parameters = @{ Identity = $UserID }
                }
            }
        )

        $Results = New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray $Requests
        $GraphRequest = foreach ($Perm in $Results) {
            if ($Perm.Trustee) {
                $Perm | Where-Object Trustee | ForEach-Object { [PSCustomObject]@{
                        User        = $_.Trustee
                        Permissions = $_.accessRights
                    }
                }
            }
            if ($Perm.AccessRights) {
                $Perm | Where-Object User | ForEach-Object { [PSCustomObject]@{
                        User        = $_.User
                        Permissions = $_.AccessRights -join ', '
                    }
                }
            }
            if ($Perm.GrantSendonBehalfTo -ne $null) {
                $Perm.GrantSendonBehalfTo | ForEach-Object { [PSCustomObject]@{
                        User        = $_
                        Permissions = 'SendOnBehalf'
                    }
                }
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        $StatusCode = [HttpStatusCode]::Forbidden
        $GraphRequest = $ErrorMessage
    }
    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })
}

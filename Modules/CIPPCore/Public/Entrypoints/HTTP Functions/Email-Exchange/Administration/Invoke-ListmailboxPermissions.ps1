function Invoke-ListmailboxPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Query.tenantFilter
    $UserID = $Request.Query.userId
    $UseReportDB = $Request.Query.UseReportDB
    $ByUser = $Request.Query.ByUser

    try {
        # If UseReportDB is specified and no specific UserID, retrieve from report database
        if ($UseReportDB -eq 'true' -and -not $UserID) {

            # Call the report function with proper parameters
            $ReportParams = @{
                TenantFilter = $TenantFilter
            }
            if ($ByUser -eq 'true') {
                $ReportParams.ByUser = $true
            }
            try {
                $GraphRequest = Get-CIPPMailboxPermissionReport @ReportParams
                $StatusCode = [HttpStatusCode]::OK
            } catch {
                $StatusCode = [HttpStatusCode]::InternalServerError
                $GraphRequest = $_.Exception.Message
            }

            return ([HttpResponseContext]@{
                    StatusCode = $StatusCode
                    Body       = @($GraphRequest)
                })
        }

        # Original live query logic for specific user
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
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($GraphRequest)
        })
}

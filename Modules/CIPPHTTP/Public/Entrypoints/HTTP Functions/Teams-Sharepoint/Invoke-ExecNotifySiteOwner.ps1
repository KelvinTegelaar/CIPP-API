function Invoke-ExecNotifySiteOwner {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    $DisplayName = $Request.Body.DisplayName
    $SiteUrl = $Request.Body.SiteUrl
    $OwnerEmail = $Request.Body.OwnerEmail
    $Type = $Request.Body.Type
    $CustomMessage = $Request.Body.CustomMessage
    $UsedGB = $Request.Body.StorageUsedGB
    $AllocatedGB = $Request.Body.StorageAllocatedGB

    try {
        if (-not $TenantFilter) { throw 'tenantFilter is required' }
        if (-not $OwnerEmail) { throw 'OwnerEmail is required — this site has no resolvable owner email' }
        if ($Type -eq 'Custom' -and -not $CustomMessage) { throw 'CustomMessage is required when Type is Custom' }

        $SiteLabel = if ($DisplayName) { $DisplayName } else { $SiteUrl }
        $StorageLine = if ($UsedGB -and $AllocatedGB) {
            $Pct = [math]::Round(([double]$UsedGB / [double]$AllocatedGB) * 100)
            "<p>Current usage: <strong>$UsedGB GB of $AllocatedGB GB allocated ($Pct%)</strong>.</p>"
        } else { '' }

        $Subject, $BodyHtml = switch ($Type) {
            'StorageCritical' {
                "Action needed: SharePoint site '$SiteLabel' is running out of storage",
                "<p>Hello,</p><p>You are listed as the owner of the SharePoint site <a href='$SiteUrl'>$SiteLabel</a>, which is approaching its storage limit.</p>$StorageLine<p>Please review the site's content and delete or archive files that are no longer needed. Old file versions and large media files are common culprits. If the site genuinely needs more space, reply to this email to request a storage increase.</p><p>Thank you,<br/>Your IT team</p>"
            }
            'Inactivity' {
                "Is the SharePoint site '$SiteLabel' still needed?",
                "<p>Hello,</p><p>You are listed as the owner of the SharePoint site <a href='$SiteUrl'>$SiteLabel</a>, which has had no activity for more than 90 days.</p><p>If the site is no longer needed, please let us know so it can be archived or removed. If it is still in use, no action is required.</p><p>Thank you,<br/>Your IT team</p>"
            }
            'Custom' {
                "A message about your SharePoint site '$SiteLabel'",
                "<p>Hello,</p><p>You are listed as the owner of the SharePoint site <a href='$SiteUrl'>$SiteLabel</a>.</p><p>$CustomMessage</p>$StorageLine<p>Thank you,<br/>Your IT team</p>"
            }
            default { throw "Invalid Type '$Type'. Valid values: StorageCritical, Inactivity, Custom" }
        }

        $MailBody = [pscustomobject]@{
            message         = @{
                subject      = $Subject
                body         = @{ contentType = 'HTML'; content = $BodyHtml }
                toRecipients = @(@{ emailAddress = @{ address = $OwnerEmail } })
            }
            saveToSentItems = 'false'
        }
        $JSONBody = ConvertTo-Json -Compress -Depth 10 -InputObject $MailBody
        $null = New-GraphPostRequest -uri 'https://graph.microsoft.com/v1.0/me/sendMail' -tenantid $env:TenantID -NoAuthCheck $true -type POST -body $JSONBody

        $Results = "Notification email ($Type) sent to $OwnerEmail for site '$SiteLabel'."
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Info

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ Results = $Results }
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $ErrorText = $ErrorMessage.NormalizedError
        if ($ErrorText -match 'MailboxNotEnabledForRESTAPI|mailbox') {
            $ErrorText = "The CIPP service account does not have a usable mailbox to send from. Original error: $ErrorText"
        }
        $Results = "Failed to send owner notification. Error: $ErrorText"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage

        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ Results = $Results }
            })
    }
}

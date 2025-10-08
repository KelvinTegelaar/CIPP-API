Function Invoke-AddSpamFilterTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Spamfilter.ReadWrite
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    try {
        $GUID = (New-Guid).GUID
        $JSON = if ($Request.Body.PowerShellCommand) {
            Write-Host 'PowerShellCommand'
            $Request.Body.PowerShellCommand | ConvertFrom-Json
        } else {
        ([pscustomobject]$Request.Body | Select-Object name, AddXHeaderValue, AdminDisplayName, AllowedSenderDomains, AllowedSenders, BlockedSenderDomains, BlockedSenders, BulkQuarantineTag, BulkSpamAction, BulkThreshold, Confirm, DownloadLink, EnableEndUserSpamNotifications, EnableLanguageBlockList, EnableRegionBlockList, EndUserSpamNotificationCustomFromAddress, EndUserSpamNotificationCustomFromName, EndUserSpamNotificationCustomSubject, EndUserSpamNotificationFrequency, EndUserSpamNotificationLanguage, EndUserSpamNotificationCustomFromAddress, HighConfidencePhishAction, HighConfidencePhishQuarantineTag, HighConfidenceSpamAction, HighConfidenceSpamQuarantineTag, IncreaseScoreWithBizOrInfoUrls, IncreaseScoreWithImageLinks, IncreaseScoreWithNumericIps, IncreaseScoreWithRedirectToOtherPort, InlineSafetyTipsEnabled, LanguageBlockList, MarkAsSpamBulkMail, MarkAsSpamEmbedTagsInHtml, MarkAsSpamEmptyMessages, MarkAsSpamFormTagsInHtml, MarkAsSpamFramesInHtml, MarkAsSpamFromAddressAuthFail, MarkAsSpamJavaScriptInHtml, MarkAsSpamNdrBackscatter, MarkAsSpamObjectTagsInHtml, MarkAsSpamSensitiveWordList, MarkAsSpamSpfRecordHardFail, MarkAsSpamWebBugsInHtml, ModifySubjectValue, PhishQuarantineTag, PhishSpamAction, PhishZapEnabled, QuarantineRetentionPeriod, RecommendedPolicyType, RedirectToRecipients, RegionBlockList, SpamAction, SpamQuarantineTag, SpamZapEnabled, TestModeAction, TestModeBccToRecipients ) | ForEach-Object {
                $NonEmptyProperties = $_.PSObject.Properties | Where-Object { $null -ne $_.Value } | Select-Object -ExpandProperty Name
                $_ | Select-Object -Property $NonEmptyProperties
            }
        }
        $JSON = ($JSON | Select-Object @{n = 'name'; e = { $_.name } }, @{n = 'comments'; e = { $_.comments } }, * | ConvertTo-Json -Depth 10)
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$json"
            RowKey       = "$GUID"
            PartitionKey = 'SpamfilterTemplate'
        }
        $Result = "Successfully created Spam Filter Template: $($Request.Body.name) with GUID $GUID"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Debug'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to create Spam Filter Template: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }


    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Result }
        })

}

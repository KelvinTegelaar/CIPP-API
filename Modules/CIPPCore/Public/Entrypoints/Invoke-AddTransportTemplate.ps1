using namespace System.Net

Function Invoke-AddTransportTemplate {
    <#
    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message 'Accessed this API' -Sev 'Debug'
    Write-Host ($request | ConvertTo-Json -Compress)

    try {        
        $GUID = (New-Guid).GUID
        $JSON = if ($request.body.PowerShellCommand) {
            Write-Host 'PowerShellCommand'
            $request.body.PowerShellCommand | ConvertFrom-Json
        }
        else {
        ([pscustomobject]$Request.body | Select-Object Name, ActivationDate, ADComparisonAttribute, ADComparisonOperator, AddManagerAsRecipientType, AddToRecipients, AnyOfCcHeader, AnyOfCcHeaderMemberOf, AnyOfRecipientAddressContainsWords, AnyOfRecipientAddressMatchesPatterns, AnyOfToCcHeader, AnyOfToCcHeaderMemberOf, AnyOfToHeader, AnyOfToHeaderMemberOf, ApplyClassification, ApplyHtmlDisclaimerFallbackAction, ApplyHtmlDisclaimerLocation, ApplyHtmlDisclaimerText, ApplyOME, ApplyRightsProtectionCustomizationTemplate, ApplyRightsProtectionTemplate, AttachmentContainsWords, AttachmentExtensionMatchesWords, AttachmentHasExecutableContent, AttachmentIsPasswordProtected, AttachmentIsUnsupported, AttachmentMatchesPatterns, AttachmentNameMatchesPatterns, AttachmentProcessingLimitExceeded, AttachmentPropertyContainsWords, AttachmentSizeOver, BetweenMemberOf1, BetweenMemberOf2, BlindCopyTo, Comments, Confirm, ContentCharacterSetContainsWords, CopyTo, DeleteMessage, DlpPolicy, DomainController, Enabled, ExceptIfADComparisonAttribute, ExceptIfADComparisonOperator, ExceptIfAnyOfCcHeader, ExceptIfAnyOfCcHeaderMemberOf, ExceptIfAnyOfRecipientAddressContainsWords, ExceptIfAnyOfRecipientAddressMatchesPatterns, ExceptIfAnyOfToCcHeader, ExceptIfAnyOfToCcHeaderMemberOf, ExceptIfAnyOfToHeader, ExceptIfAnyOfToHeaderMemberOf, ExceptIfAttachmentContainsWords, ExceptIfAttachmentExtensionMatchesWords, ExceptIfAttachmentHasExecutableContent, ExceptIfAttachmentIsPasswordProtected, ExceptIfAttachmentIsUnsupported, ExceptIfAttachmentMatchesPatterns, ExceptIfAttachmentNameMatchesPatterns, ExceptIfAttachmentProcessingLimitExceeded, ExceptIfAttachmentPropertyContainsWords, ExceptIfAttachmentSizeOver, ExceptIfBetweenMemberOf1, ExceptIfBetweenMemberOf2, ExceptIfContentCharacterSetContainsWords, ExceptIfFrom, ExceptIfFromAddressContainsWords, ExceptIfFromAddressMatchesPatterns, ExceptIfFromMemberOf, ExceptIfFromScope, ExceptIfHasClassification, ExceptIfHasNoClassification, ExceptIfHasSenderOverride, ExceptIfHeaderContainsMessageHeader, ExceptIfHeaderContainsWords, ExceptIfHeaderMatchesMessageHeader, ExceptIfHeaderMatchesPatterns, ExceptIfManagerAddresses, ExceptIfManagerForEvaluatedUser, ExceptIfMessageContainsDataClassifications, ExceptIfMessageSizeOver, ExceptIfMessageTypeMatches, ExceptIfRecipientADAttributeContainsWords, ExceptIfRecipientADAttributeMatchesPatterns, ExceptIfRecipientAddressContainsWords, ExceptIfRecipientAddressMatchesPatterns, ExceptIfRecipientDomainIs, ExceptIfRecipientInSenderList, ExceptIfSCLOver, ExceptIfSenderADAttributeContainsWords, ExceptIfSenderADAttributeMatchesPatterns, ExceptIfSenderDomainIs, ExceptIfSenderInRecipientList, ExceptIfSenderIpRanges, ExceptIfSenderManagementRelationship, ExceptIfSentTo, ExceptIfSentToMemberOf, ExceptIfSentToScope, ExceptIfSubjectContainsWords, ExceptIfSubjectMatchesPatterns, ExceptIfSubjectOrBodyContainsWords, ExceptIfSubjectOrBodyMatchesPatterns, ExceptIfWithImportance, ExpiryDate, From, FromAddressContainsWords, FromAddressMatchesPatterns, FromMemberOf, FromScope, GenerateIncidentReport, GenerateNotification, HasClassification, HasNoClassification, HasSenderOverride, HeaderContainsMessageHeader, HeaderContainsWords, HeaderMatchesMessageHeader, HeaderMatchesPatterns, IncidentReportContent, IncidentReportOriginalMail, LogEventText, ManagerAddresses, ManagerForEvaluatedUser, MessageContainsDataClassifications, MessageSizeOver, MessageTypeMatches, Mode, ModerateMessageByManager, ModerateMessageByUser, NotifySender, PrependSubject, Quarantine, RecipientADAttributeContainsWords, RecipientADAttributeMatchesPatterns, RecipientAddressContainsWords, RecipientAddressMatchesPatterns, RecipientAddressType, RecipientDomainIs, RecipientInSenderList, RedirectMessageTo, RejectMessageEnhancedStatusCode, RejectMessageReasonText, RemoveHeader, RemoveOME, RemoveOMEv2, RemoveRMSAttachmentEncryption, RouteMessageOutboundConnector, RouteMessageOutboundRequireTls, RuleErrorAction, RuleSubType, SCLOver, SenderADAttributeContainsWords, SenderADAttributeMatchesPatterns, SenderAddressLocation, SenderDomainIs, SenderInRecipientList, SenderIpRanges, SenderManagementRelationship, SentTo, SentToMemberOf, SentToScope, SetAuditSeverity, SetHeaderName, SetHeaderValue, SetSCL, SmtpRejectMessageRejectStatusCode, SmtpRejectMessageRejectText, StopRuleProcessing, SubjectContainsWords, SubjectMatchesPatterns, SubjectOrBodyContainsWords, SubjectOrBodyMatchesPatterns, UseLegacyRegex, WithImportance ) | ForEach-Object {
                $NonEmptyProperties = $_.psobject.Properties | Where-Object { $null -ne $_.Value } | Select-Object -ExpandProperty Name
                $_ | Select-Object -Property $NonEmptyProperties 
            }
        }
        $JSON = ($JSON | Select-Object @{n = 'name'; e = { $_.name } }, @{n = 'comments'; e = { $_.comments } }, * | ConvertTo-Json -Depth 10)
        $Table = Get-CippTable -tablename 'templates'
        $Table.Force = $true
        Add-CIPPAzDataTableEntity @Table -Entity @{
            JSON         = "$json"
            RowKey       = "$GUID"
            PartitionKey = 'TransportTemplate'
        }
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Created Transport Rule Template $($Request.body.name) with GUID $GUID" -Sev 'Debug'
        $body = [pscustomobject]@{'Results' = 'Successfully added template' }
    
    }
    catch {
        Write-LogMessage -user $request.headers.'x-ms-client-principal' -API $APINAME -message "Failed to create Transport Rule Template: $($_.Exception.Message)" -Sev 'Error'
        $body = [pscustomobject]@{'Results' = "Intune Template Deployment failed: $($_.Exception.Message)" }
    }


    # Associate values to output bindings by calling 'Push-OutputBinding'.
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $body
        })

}

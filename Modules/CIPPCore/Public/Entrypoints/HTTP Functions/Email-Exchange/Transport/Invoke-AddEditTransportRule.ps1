function Invoke-AddEditTransportRule {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.TransportRule.ReadWrite
    .DESCRIPTION
        This function creates a new transport rule or edits an existing one (mail flow rule).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    # Interact with query parameters or the body of the request.
    $TenantFilter = $Request.Body.tenantFilter

    if (!$TenantFilter) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = 'TenantFilter is required'
            })
        return
    }

    # Extract basic rule settings from body
    $Identity = $Request.Body.ruleId
    $Name = $Request.Body.Name
    $Priority = $Request.Body.Priority
    $Comments = $Request.Body.Comments
    $Mode = $Request.Body.Mode
    $SetAuditSeverity = $Request.Body.SetAuditSeverity
    $State = $Request.Body.State
    $CmdletState = $Request.Body.State ?? $Request.Body.Enabled
    $Enabled = $Request.Body.Enabled
    $StopRuleProcessing = $Request.Body.StopRuleProcessing
    $SenderAddressLocation = $Request.Body.SenderAddressLocation
    $ActivationDate = $Request.Body.ActivationDate
    $ExpiryDate = $Request.Body.ExpiryDate

    # Extract condition fields
    $From = $Request.Body.From
    $FromScope = $Request.Body.FromScope
    $FromMemberOf = $Request.Body.FromMemberOf
    $SentTo = $Request.Body.SentTo
    $SentToScope = $Request.Body.SentToScope
    $SentToMemberOf = $Request.Body.SentToMemberOf
    $SubjectContainsWords = $Request.Body.SubjectContainsWords
    $SubjectMatchesPatterns = $Request.Body.SubjectMatchesPatterns
    $SubjectOrBodyContainsWords = $Request.Body.SubjectOrBodyContainsWords
    $SubjectOrBodyMatchesPatterns = $Request.Body.SubjectOrBodyMatchesPatterns
    $FromAddressContainsWords = $Request.Body.FromAddressContainsWords
    $FromAddressMatchesPatterns = $Request.Body.FromAddressMatchesPatterns
    $AttachmentContainsWords = $Request.Body.AttachmentContainsWords
    $AttachmentMatchesPatterns = $Request.Body.AttachmentMatchesPatterns
    $AttachmentExtensionMatchesWords = $Request.Body.AttachmentExtensionMatchesWords
    $AttachmentSizeOver = $Request.Body.AttachmentSizeOver
    $MessageSizeOver = $Request.Body.MessageSizeOver
    $SCLOver = $Request.Body.SCLOver
    $WithImportance = $Request.Body.WithImportance
    $MessageTypeMatches = $Request.Body.MessageTypeMatches
    $SenderDomainIs = $Request.Body.SenderDomainIs
    $RecipientDomainIs = $Request.Body.RecipientDomainIs
    $RecipientAddressContainsWords = $Request.Body.RecipientAddressContainsWords
    $RecipientAddressMatchesPatterns = $Request.Body.RecipientAddressMatchesPatterns
    $AnyOfRecipientAddressContainsWords = $Request.Body.AnyOfRecipientAddressContainsWords
    $AnyOfRecipientAddressMatchesPatterns = $Request.Body.AnyOfRecipientAddressMatchesPatterns
    $AnyOfToHeader = $Request.Body.AnyOfToHeader
    $AnyOfToHeaderMemberOf = $Request.Body.AnyOfToHeaderMemberOf
    $AnyOfCcHeader = $Request.Body.AnyOfCcHeader
    $AnyOfCcHeaderMemberOf = $Request.Body.AnyOfCcHeaderMemberOf
    $AnyOfToCcHeader = $Request.Body.AnyOfToCcHeader
    $AnyOfToCcHeaderMemberOf = $Request.Body.AnyOfToCcHeaderMemberOf
    $HeaderContainsWords = $Request.Body.HeaderContainsWords
    $HeaderContainsWordsMessageHeader = $Request.Body.HeaderContainsWordsMessageHeader
    $HeaderMatchesPatterns = $Request.Body.HeaderMatchesPatterns
    $HeaderMatchesPatternsMessageHeader = $Request.Body.HeaderMatchesPatternsMessageHeader
    $SenderIpRanges = $Request.Body.SenderIpRanges

    # Extract action fields
    $DeleteMessage = $Request.Body.DeleteMessage
    $Quarantine = $Request.Body.Quarantine
    $RedirectMessageTo = $Request.Body.RedirectMessageTo
    $BlindCopyTo = $Request.Body.BlindCopyTo
    $CopyTo = $Request.Body.CopyTo
    $ModerateMessageByUser = $Request.Body.ModerateMessageByUser
    $ModerateMessageByManager = $Request.Body.ModerateMessageByManager
    $RejectMessageReasonText = $Request.Body.RejectMessageReasonText
    $RejectMessageEnhancedStatusCode = $Request.Body.RejectMessageEnhancedStatusCode
    $PrependSubject = $Request.Body.PrependSubject
    $SetSCL = $Request.Body.SetSCL
    $SetHeaderName = $Request.Body.SetHeaderName
    $SetHeaderValue = $Request.Body.SetHeaderValue
    $RemoveHeader = $Request.Body.RemoveHeader
    $ApplyClassification = $Request.Body.ApplyClassification
    $ApplyHtmlDisclaimerText = $Request.Body.ApplyHtmlDisclaimerText
    $ApplyHtmlDisclaimerLocation = $Request.Body.ApplyHtmlDisclaimerLocation
    $ApplyHtmlDisclaimerFallbackAction = $Request.Body.ApplyHtmlDisclaimerFallbackAction
    $GenerateIncidentReport = $Request.Body.GenerateIncidentReport
    $GenerateNotification = $Request.Body.GenerateNotification
    $ApplyOME = $Request.Body.ApplyOME

    # Extract exception fields (ExceptIf versions)
    $ExceptIfFrom = $Request.Body.ExceptIfFrom
    $ExceptIfFromScope = $Request.Body.ExceptIfFromScope
    $ExceptIfFromMemberOf = $Request.Body.ExceptIfFromMemberOf
    $ExceptIfSentTo = $Request.Body.ExceptIfSentTo
    $ExceptIfSentToScope = $Request.Body.ExceptIfSentToScope
    $ExceptIfSentToMemberOf = $Request.Body.ExceptIfSentToMemberOf
    $ExceptIfSubjectContainsWords = $Request.Body.ExceptIfSubjectContainsWords
    $ExceptIfSubjectMatchesPatterns = $Request.Body.ExceptIfSubjectMatchesPatterns
    $ExceptIfSubjectOrBodyContainsWords = $Request.Body.ExceptIfSubjectOrBodyContainsWords
    $ExceptIfSubjectOrBodyMatchesPatterns = $Request.Body.ExceptIfSubjectOrBodyMatchesPatterns
    $ExceptIfFromAddressContainsWords = $Request.Body.ExceptIfFromAddressContainsWords
    $ExceptIfFromAddressMatchesPatterns = $Request.Body.ExceptIfFromAddressMatchesPatterns
    $ExceptIfAttachmentContainsWords = $Request.Body.ExceptIfAttachmentContainsWords
    $ExceptIfAttachmentMatchesPatterns = $Request.Body.ExceptIfAttachmentMatchesPatterns
    $ExceptIfAttachmentExtensionMatchesWords = $Request.Body.ExceptIfAttachmentExtensionMatchesWords
    $ExceptIfAttachmentSizeOver = $Request.Body.ExceptIfAttachmentSizeOver
    $ExceptIfMessageSizeOver = $Request.Body.ExceptIfMessageSizeOver
    $ExceptIfSCLOver = $Request.Body.ExceptIfSCLOver
    $ExceptIfWithImportance = $Request.Body.ExceptIfWithImportance
    $ExceptIfMessageTypeMatches = $Request.Body.ExceptIfMessageTypeMatches
    $ExceptIfSenderDomainIs = $Request.Body.ExceptIfSenderDomainIs
    $ExceptIfRecipientDomainIs = $Request.Body.ExceptIfRecipientDomainIs
    $ExceptIfRecipientAddressContainsWords = $Request.Body.ExceptIfRecipientAddressContainsWords
    $ExceptIfRecipientAddressMatchesPatterns = $Request.Body.ExceptIfRecipientAddressMatchesPatterns
    $ExceptIfAnyOfRecipientAddressContainsWords = $Request.Body.ExceptIfAnyOfRecipientAddressContainsWords
    $ExceptIfAnyOfRecipientAddressMatchesPatterns = $Request.Body.ExceptIfAnyOfRecipientAddressMatchesPatterns
    $ExceptIfAnyOfToHeader = $Request.Body.ExceptIfAnyOfToHeader
    $ExceptIfAnyOfToHeaderMemberOf = $Request.Body.ExceptIfAnyOfToHeaderMemberOf
    $ExceptIfAnyOfCcHeader = $Request.Body.ExceptIfAnyOfCcHeader
    $ExceptIfAnyOfCcHeaderMemberOf = $Request.Body.ExceptIfAnyOfCcHeaderMemberOf
    $ExceptIfAnyOfToCcHeader = $Request.Body.ExceptIfAnyOfToCcHeader
    $ExceptIfAnyOfToCcHeaderMemberOf = $Request.Body.ExceptIfAnyOfToCcHeaderMemberOf
    $ExceptIfHeaderContainsWords = $Request.Body.ExceptIfHeaderContainsWords
    $ExceptIfHeaderContainsWordsMessageHeader = $Request.Body.ExceptIfHeaderContainsWordsMessageHeader
    $ExceptIfHeaderMatchesPatterns = $Request.Body.ExceptIfHeaderMatchesPatterns
    $ExceptIfHeaderMatchesPatternsMessageHeader = $Request.Body.ExceptIfHeaderMatchesPatternsMessageHeader
    $ExceptIfSenderIpRanges = $Request.Body.ExceptIfSenderIpRanges

    # Helper function to process array fields
    function Process-ArrayField {
        param (
            [Parameter(Mandatory = $false)]
            $Field
        )

        if ($null -eq $Field) { return @() }

        # If already an array, process each item
        if ($Field -is [array]) {
            $result = [System.Collections.ArrayList]@()
            foreach ($item in $Field) {
                if ($item -is [string]) {
                    $result.Add($item) | Out-Null
                } elseif ($item -is [hashtable] -or $item -is [PSCustomObject]) {
                    # Extract value from object
                    if ($null -ne $item.value) {
                        $result.Add($item.value) | Out-Null
                    } elseif ($null -ne $item.userPrincipalName) {
                        $result.Add($item.userPrincipalName) | Out-Null
                    } elseif ($null -ne $item.id) {
                        $result.Add($item.id) | Out-Null
                    } else {
                        $result.Add($item.ToString()) | Out-Null
                    }
                } else {
                    $result.Add($item.ToString()) | Out-Null
                }
            }
            return $result.ToArray()
        }

        # If it's a single object
        if ($Field -is [hashtable] -or $Field -is [PSCustomObject]) {
            if ($null -ne $Field.value) { return @($Field.value) }
            if ($null -ne $Field.userPrincipalName) { return @($Field.userPrincipalName) }
            if ($null -ne $Field.id) { return @($Field.id) }
        }

        # If it's a string, return as an array with one item
        if ($Field -is [string]) {
            return @($Field)
        }

        return @($Field)
    }

    # Helper function to process comma-separated text fields into arrays
    function Process-TextArrayField {
        param (
            [Parameter(Mandatory = $false)]
            $Field
        )

        if ($null -eq $Field -or $Field -eq '') { return @() }

        if ($Field -is [array]) {
            return $Field
        }

        if ($Field -is [string]) {
            # Split by comma and trim whitespace
            return ($Field -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        }

        return @($Field)
    }

    # Convert state to bool when creating new rule
    if ($State -eq "Disabled") {
        $State = $false
    }

    if ($State -eq "Enabled") {
        $State = $true
    }

    if ($Enabled -eq "Disabled") {
        $State = $false
    }

    if ($Enabled -eq "Enabled") {
        $State = $true
    }

    # Process array fields for recipients/users
    $From = Process-ArrayField -Field $From
    $FromMemberOf = Process-ArrayField -Field $FromMemberOf
    $SentTo = Process-ArrayField -Field $SentTo
    $SentToMemberOf = Process-ArrayField -Field $SentToMemberOf
    $AnyOfToHeader = Process-ArrayField -Field $AnyOfToHeader
    $AnyOfToHeaderMemberOf = Process-ArrayField -Field $AnyOfToHeaderMemberOf
    $AnyOfCcHeader = Process-ArrayField -Field $AnyOfCcHeader
    $AnyOfCcHeaderMemberOf = Process-ArrayField -Field $AnyOfCcHeaderMemberOf
    $AnyOfToCcHeader = Process-ArrayField -Field $AnyOfToCcHeader
    $AnyOfToCcHeaderMemberOf = Process-ArrayField -Field $AnyOfToCcHeaderMemberOf
    $RedirectMessageTo = Process-ArrayField -Field $RedirectMessageTo
    $BlindCopyTo = Process-ArrayField -Field $BlindCopyTo
    $CopyTo = Process-ArrayField -Field $CopyTo
    $ModerateMessageByUser = Process-ArrayField -Field $ModerateMessageByUser
    $ExceptIfFrom = Process-ArrayField -Field $ExceptIfFrom
    $ExceptIfFromMemberOf = Process-ArrayField -Field $ExceptIfFromMemberOf
    $ExceptIfSentTo = Process-ArrayField -Field $ExceptIfSentTo
    $ExceptIfSentToMemberOf = Process-ArrayField -Field $ExceptIfSentToMemberOf
    $ExceptIfAnyOfToHeader = Process-ArrayField -Field $ExceptIfAnyOfToHeader
    $ExceptIfAnyOfToHeaderMemberOf = Process-ArrayField -Field $ExceptIfAnyOfToHeaderMemberOf
    $ExceptIfAnyOfCcHeader = Process-ArrayField -Field $ExceptIfAnyOfCcHeader
    $ExceptIfAnyOfCcHeaderMemberOf = Process-ArrayField -Field $ExceptIfAnyOfCcHeaderMemberOf
    $ExceptIfAnyOfToCcHeader = Process-ArrayField -Field $ExceptIfAnyOfToCcHeader
    $ExceptIfAnyOfToCcHeaderMemberOf = Process-ArrayField -Field $ExceptIfAnyOfToCcHeaderMemberOf
    $SenderDomainIs = Process-ArrayField -Field $SenderDomainIs
    $RecipientDomainIs = Process-ArrayField -Field $RecipientDomainIs
    $ExceptIfSenderDomainIs = Process-ArrayField -Field $ExceptIfSenderDomainIs
    $ExceptIfRecipientDomainIs = Process-ArrayField -Field $ExceptIfRecipientDomainIs

    # Process text array fields (comma-separated strings)
    $SubjectContainsWords = Process-TextArrayField -Field $SubjectContainsWords
    $SubjectMatchesPatterns = Process-TextArrayField -Field $SubjectMatchesPatterns
    $SubjectOrBodyContainsWords = Process-TextArrayField -Field $SubjectOrBodyContainsWords
    $SubjectOrBodyMatchesPatterns = Process-TextArrayField -Field $SubjectOrBodyMatchesPatterns
    $FromAddressContainsWords = Process-TextArrayField -Field $FromAddressContainsWords
    $FromAddressMatchesPatterns = Process-TextArrayField -Field $FromAddressMatchesPatterns
    $AttachmentContainsWords = Process-TextArrayField -Field $AttachmentContainsWords
    $AttachmentMatchesPatterns = Process-TextArrayField -Field $AttachmentMatchesPatterns
    $AttachmentExtensionMatchesWords = Process-TextArrayField -Field $AttachmentExtensionMatchesWords
    $RecipientAddressContainsWords = Process-TextArrayField -Field $RecipientAddressContainsWords
    $RecipientAddressMatchesPatterns = Process-TextArrayField -Field $RecipientAddressMatchesPatterns
    $AnyOfRecipientAddressContainsWords = Process-TextArrayField -Field $AnyOfRecipientAddressContainsWords
    $AnyOfRecipientAddressMatchesPatterns = Process-TextArrayField -Field $AnyOfRecipientAddressMatchesPatterns
    $HeaderContainsWords = Process-TextArrayField -Field $HeaderContainsWords
    $HeaderMatchesPatterns = Process-TextArrayField -Field $HeaderMatchesPatterns

    # Process exception text array fields
    $ExceptIfSubjectContainsWords = Process-TextArrayField -Field $ExceptIfSubjectContainsWords
    $ExceptIfSubjectMatchesPatterns = Process-TextArrayField -Field $ExceptIfSubjectMatchesPatterns
    $ExceptIfSubjectOrBodyContainsWords = Process-TextArrayField -Field $ExceptIfSubjectOrBodyContainsWords
    $ExceptIfSubjectOrBodyMatchesPatterns = Process-TextArrayField -Field $ExceptIfSubjectOrBodyMatchesPatterns
    $ExceptIfFromAddressContainsWords = Process-TextArrayField -Field $ExceptIfFromAddressContainsWords
    $ExceptIfFromAddressMatchesPatterns = Process-TextArrayField -Field $ExceptIfFromAddressMatchesPatterns
    $ExceptIfAttachmentContainsWords = Process-TextArrayField -Field $ExceptIfAttachmentContainsWords
    $ExceptIfAttachmentMatchesPatterns = Process-TextArrayField -Field $ExceptIfAttachmentMatchesPatterns
    $ExceptIfAttachmentExtensionMatchesWords = Process-TextArrayField -Field $ExceptIfAttachmentExtensionMatchesWords
    $ExceptIfRecipientAddressContainsWords = Process-TextArrayField -Field $ExceptIfRecipientAddressContainsWords
    $ExceptIfRecipientAddressMatchesPatterns = Process-TextArrayField -Field $ExceptIfRecipientAddressMatchesPatterns
    $ExceptIfAnyOfRecipientAddressContainsWords = Process-TextArrayField -Field $ExceptIfAnyOfRecipientAddressContainsWords
    $ExceptIfAnyOfRecipientAddressMatchesPatterns = Process-TextArrayField -Field $ExceptIfAnyOfRecipientAddressMatchesPatterns
    $ExceptIfHeaderContainsWords = Process-TextArrayField -Field $ExceptIfHeaderContainsWords
    $ExceptIfHeaderMatchesPatterns = Process-TextArrayField -Field $ExceptIfHeaderMatchesPatterns

    # Process IP range fields
    $SenderIpRanges = Process-TextArrayField -Field $SenderIpRanges
    $ExceptIfSenderIpRanges = Process-TextArrayField -Field $ExceptIfSenderIpRanges

    try {
        # Build command parameters for transport rule
        $ruleParams = @{
            Name = $Name
        }

        # If editing existing rule add Identity
        if ($null -ne $Identity) { $ruleParams.Add('Identity', $Identity) }

        # State uses a different cmdlet for updating an existing rule so extract the required data to enable or disable it
        $CmdletState = if ($CmdletState -eq 'Enabled') { 'Enable-TransportRule' } else { 'Disable-TransportRule' }

        # Basic parameters
        if (($null -ne $State) -and (!$Identity)) { $ruleParams.Add('Enabled', $State) }
        if ($null -ne $Priority) { $ruleParams.Add('Priority', $Priority) }
        if ($null -ne $Comments) { $ruleParams.Add('Comments', $Comments) }
        if ($null -ne $Mode) {
            $modeValue = if ($Mode.value) { $Mode.value } else { $Mode }
            $ruleParams.Add('Mode', $modeValue)
        }
        if ($null -ne $SetAuditSeverity) {
            $severityValue = if ($SetAuditSeverity.value) { $SetAuditSeverity.value } else { $SetAuditSeverity }
            if ($severityValue -ne '') {
                $ruleParams.Add('SetAuditSeverity', $severityValue)
            }
        }
        if ($null -ne $StopRuleProcessing) { $ruleParams.Add('StopRuleProcessing', $StopRuleProcessing) }
        if ($null -ne $SenderAddressLocation) {
            $locationValue = if ($SenderAddressLocation.value) { $SenderAddressLocation.value } else { $SenderAddressLocation }
            $ruleParams.Add('SenderAddressLocation', $locationValue)
        }
        if ($null -ne $ActivationDate -and $ActivationDate -ne '') { $ruleParams.Add('ActivationDate', $ActivationDate) }
        if ($null -ne $ExpiryDate -and $ExpiryDate -ne '') { $ruleParams.Add('ExpiryDate', $ExpiryDate) }

        # Condition parameters
        if ($null -ne $From -and $From.Count -gt 0) { $ruleParams.Add('From', $From) }
        if ($null -ne $FromScope) {
            $fromScopeValue = if ($FromScope.value) { $FromScope.value } else { $FromScope }
            $ruleParams.Add('FromScope', $fromScopeValue)
        }
        if ($null -ne $FromMemberOf -and $FromMemberOf.Count -gt 0) { $ruleParams.Add('FromMemberOf', $FromMemberOf) }
        if ($null -ne $SentTo -and $SentTo.Count -gt 0) { $ruleParams.Add('SentTo', $SentTo) }
        if ($null -ne $SentToScope) {
            $sentToScopeValue = if ($SentToScope.value) { $SentToScope.value } else { $SentToScope }
            $ruleParams.Add('SentToScope', $sentToScopeValue)
        }
        if ($null -ne $SentToMemberOf -and $SentToMemberOf.Count -gt 0) { $ruleParams.Add('SentToMemberOf', $SentToMemberOf) }
        if ($null -ne $SubjectContainsWords -and $SubjectContainsWords.Count -gt 0) {
            $ruleParams.Add('SubjectContainsWords', $SubjectContainsWords)
        }
        if ($null -ne $SubjectMatchesPatterns -and $SubjectMatchesPatterns.Count -gt 0) {
            $ruleParams.Add('SubjectMatchesPatterns', $SubjectMatchesPatterns)
        }
        if ($null -ne $SubjectOrBodyContainsWords -and $SubjectOrBodyContainsWords.Count -gt 0) {
            $ruleParams.Add('SubjectOrBodyContainsWords', $SubjectOrBodyContainsWords)
        }
        if ($null -ne $SubjectOrBodyMatchesPatterns -and $SubjectOrBodyMatchesPatterns.Count -gt 0) {
            $ruleParams.Add('SubjectOrBodyMatchesPatterns', $SubjectOrBodyMatchesPatterns)
        }
        if ($null -ne $FromAddressContainsWords -and $FromAddressContainsWords.Count -gt 0) {
            $ruleParams.Add('FromAddressContainsWords', $FromAddressContainsWords)
        }
        if ($null -ne $FromAddressMatchesPatterns -and $FromAddressMatchesPatterns.Count -gt 0) {
            $ruleParams.Add('FromAddressMatchesPatterns', $FromAddressMatchesPatterns)
        }
        if ($null -ne $AttachmentContainsWords -and $AttachmentContainsWords.Count -gt 0) {
            $ruleParams.Add('AttachmentContainsWords', $AttachmentContainsWords)
        }
        if ($null -ne $AttachmentMatchesPatterns -and $AttachmentMatchesPatterns.Count -gt 0) {
            $ruleParams.Add('AttachmentMatchesPatterns', $AttachmentMatchesPatterns)
        }
        if ($null -ne $AttachmentExtensionMatchesWords -and $AttachmentExtensionMatchesWords.Count -gt 0) {
            $ruleParams.Add('AttachmentExtensionMatchesWords', $AttachmentExtensionMatchesWords)
        }
        if ($null -ne $AttachmentSizeOver) { $ruleParams.Add('AttachmentSizeOver', $AttachmentSizeOver) }
        if ($null -ne $MessageSizeOver) { $ruleParams.Add('MessageSizeOver', $MessageSizeOver) }
        if ($null -ne $SCLOver) {
            $sclValue = if ($SCLOver.value) { $SCLOver.value } else { $SCLOver }
            $ruleParams.Add('SCLOver', $sclValue)
        }
        if ($null -ne $WithImportance) {
            $importanceValue = if ($WithImportance.value) { $WithImportance.value } else { $WithImportance }
            $ruleParams.Add('WithImportance', $importanceValue)
        }
        if ($null -ne $MessageTypeMatches) {
            $messageTypeValue = if ($MessageTypeMatches.value) { $MessageTypeMatches.value } else { $MessageTypeMatches }
            $ruleParams.Add('MessageTypeMatches', $messageTypeValue)
        }
        if ($null -ne $SenderDomainIs -and $SenderDomainIs.Count -gt 0) {
            $ruleParams.Add('SenderDomainIs', $SenderDomainIs)
        }
        if ($null -ne $RecipientDomainIs -and $RecipientDomainIs.Count -gt 0) {
            $ruleParams.Add('RecipientDomainIs', $RecipientDomainIs)
        }
        if ($null -ne $RecipientAddressContainsWords -and $RecipientAddressContainsWords.Count -gt 0) {
            $ruleParams.Add('RecipientAddressContainsWords', $RecipientAddressContainsWords)
        }
        if ($null -ne $RecipientAddressMatchesPatterns -and $RecipientAddressMatchesPatterns.Count -gt 0) {
            $ruleParams.Add('RecipientAddressMatchesPatterns', $RecipientAddressMatchesPatterns)
        }
        if ($null -ne $AnyOfRecipientAddressContainsWords -and $AnyOfRecipientAddressContainsWords.Count -gt 0) {
            $ruleParams.Add('AnyOfRecipientAddressContainsWords', $AnyOfRecipientAddressContainsWords)
        }
        if ($null -ne $AnyOfRecipientAddressMatchesPatterns -and $AnyOfRecipientAddressMatchesPatterns.Count -gt 0) {
            $ruleParams.Add('AnyOfRecipientAddressMatchesPatterns', $AnyOfRecipientAddressMatchesPatterns)
        }
        if ($null -ne $AnyOfToHeader -and $AnyOfToHeader.Count -gt 0) {
            $ruleParams.Add('AnyOfToHeader', $AnyOfToHeader)
        }
        if ($null -ne $AnyOfToHeaderMemberOf -and $AnyOfToHeaderMemberOf.Count -gt 0) {
            $ruleParams.Add('AnyOfToHeaderMemberOf', $AnyOfToHeaderMemberOf)
        }
        if ($null -ne $AnyOfCcHeader -and $AnyOfCcHeader.Count -gt 0) {
            $ruleParams.Add('AnyOfCcHeader', $AnyOfCcHeader)
        }
        if ($null -ne $AnyOfCcHeaderMemberOf -and $AnyOfCcHeaderMemberOf.Count -gt 0) {
            $ruleParams.Add('AnyOfCcHeaderMemberOf', $AnyOfCcHeaderMemberOf)
        }
        if ($null -ne $AnyOfToCcHeader -and $AnyOfToCcHeader.Count -gt 0) {
            $ruleParams.Add('AnyOfToCcHeader', $AnyOfToCcHeader)
        }
        if ($null -ne $AnyOfToCcHeaderMemberOf -and $AnyOfToCcHeaderMemberOf.Count -gt 0) {
            $ruleParams.Add('AnyOfToCcHeaderMemberOf', $AnyOfToCcHeaderMemberOf)
        }
        if ($null -ne $HeaderContainsWords -and $HeaderContainsWords.Count -gt 0 -and $null -ne $HeaderContainsWordsMessageHeader) {
            $ruleParams.Add('HeaderContainsMessageHeader', $HeaderContainsWordsMessageHeader)
            $ruleParams.Add('HeaderContainsWords', $HeaderContainsWords)
        }
        if ($null -ne $HeaderMatchesPatterns -and $HeaderMatchesPatterns.Count -gt 0 -and $null -ne $HeaderMatchesPatternsMessageHeader) {
            $ruleParams.Add('HeaderMatchesMessageHeader', $HeaderMatchesPatternsMessageHeader)
            $ruleParams.Add('HeaderMatchesPatterns', $HeaderMatchesPatterns)
        }
        if ($null -ne $SenderIpRanges -and $SenderIpRanges.Count -gt 0) {
            $ruleParams.Add('SenderIpRanges', $SenderIpRanges)
        }

        # Action parameters
        if ($null -ne $DeleteMessage) { $ruleParams.Add('DeleteMessage', $DeleteMessage) }
        if ($null -ne $Quarantine) { $ruleParams.Add('Quarantine', $Quarantine) }
        if ($null -ne $RedirectMessageTo -and $RedirectMessageTo.Count -gt 0) {
            $ruleParams.Add('RedirectMessageTo', $RedirectMessageTo)
        }
        if ($null -ne $BlindCopyTo -and $BlindCopyTo.Count -gt 0) { $ruleParams.Add('BlindCopyTo', $BlindCopyTo) }
        if ($null -ne $CopyTo -and $CopyTo.Count -gt 0) { $ruleParams.Add('CopyTo', $CopyTo) }
        if ($null -ne $ModerateMessageByUser -and $ModerateMessageByUser.Count -gt 0) {
            $ruleParams.Add('ModerateMessageByUser', $ModerateMessageByUser)
        }
        if ($null -ne $ModerateMessageByManager) { $ruleParams.Add('ModerateMessageByManager', $ModerateMessageByManager) }
        if ($null -ne $RejectMessageReasonText -and $RejectMessageReasonText -ne '') {
            $ruleParams.Add('RejectMessageReasonText', $RejectMessageReasonText)
        }
        if ($null -ne $RejectMessageEnhancedStatusCode -and $RejectMessageEnhancedStatusCode -ne '') {
            $ruleParams.Add('RejectMessageEnhancedStatusCode', $RejectMessageEnhancedStatusCode)
        }
        if ($null -ne $PrependSubject -and $PrependSubject -ne '') { $ruleParams.Add('PrependSubject', $PrependSubject) }
        if ($null -ne $SetSCL) {
            $setSclValue = if ($SetSCL.value) { $SetSCL.value } else { $SetSCL }
            $ruleParams.Add('SetSCL', $setSclValue)
        }
        if ($null -ne $SetHeaderName -and $SetHeaderName -ne '' -and $null -ne $SetHeaderValue) {
            $ruleParams.Add('SetHeaderName', $SetHeaderName)
            $ruleParams.Add('SetHeaderValue', $SetHeaderValue)
        }
        if ($null -ne $RemoveHeader -and $RemoveHeader -ne '') { $ruleParams.Add('RemoveHeader', $RemoveHeader) }
        if ($null -ne $ApplyClassification -and $ApplyClassification -ne '') {
            $ruleParams.Add('ApplyClassification', $ApplyClassification)
        }
        if ($null -ne $ApplyHtmlDisclaimerText -and $ApplyHtmlDisclaimerText -ne '') {
            $ruleParams.Add('ApplyHtmlDisclaimerText', $ApplyHtmlDisclaimerText)
            if ($null -ne $ApplyHtmlDisclaimerLocation) {
                $disclaimerLocationValue = if ($ApplyHtmlDisclaimerLocation.value) { $ApplyHtmlDisclaimerLocation.value } else { $ApplyHtmlDisclaimerLocation }
                $ruleParams.Add('ApplyHtmlDisclaimerLocation', $disclaimerLocationValue)
            }
            if ($null -ne $ApplyHtmlDisclaimerFallbackAction) {
                $disclaimerFallbackValue = if ($ApplyHtmlDisclaimerFallbackAction.value) { $ApplyHtmlDisclaimerFallbackAction.value } else { $ApplyHtmlDisclaimerFallbackAction }
                $ruleParams.Add('ApplyHtmlDisclaimerFallbackAction', $disclaimerFallbackValue)
            }
        }
        if ($null -ne $GenerateIncidentReport -and $GenerateIncidentReport.Count -gt 0) {
            $ruleParams.Add('GenerateIncidentReport', $GenerateIncidentReport)
        }
        if ($null -ne $GenerateNotification -and $GenerateNotification -ne '') {
            $ruleParams.Add('GenerateNotification', $GenerateNotification)
        }
        if ($null -ne $ApplyOME) { $ruleParams.Add('ApplyOME', $ApplyOME) }

        # Exception parameters (ExceptIf versions)
        if ($null -ne $ExceptIfFrom -and $ExceptIfFrom.Count -gt 0) { $ruleParams.Add('ExceptIfFrom', $ExceptIfFrom) }
        if ($null -ne $ExceptIfFromScope) {
            $exceptFromScopeValue = if ($ExceptIfFromScope.value) { $ExceptIfFromScope.value } else { $ExceptIfFromScope }
            $ruleParams.Add('ExceptIfFromScope', $exceptFromScopeValue)
        }
        if ($null -ne $ExceptIfFromMemberOf -and $ExceptIfFromMemberOf.Count -gt 0) { $ruleParams.Add('ExceptIfFromMemberOf', $ExceptIfFromMemberOf) }
        if ($null -ne $ExceptIfSentTo -and $ExceptIfSentTo.Count -gt 0) { $ruleParams.Add('ExceptIfSentTo', $ExceptIfSentTo) }
        if ($null -ne $ExceptIfSentToScope) {
            $exceptSentToScopeValue = if ($ExceptIfSentToScope.value) { $ExceptIfSentToScope.value } else { $ExceptIfSentToScope }
            $ruleParams.Add('ExceptIfSentToScope', $exceptSentToScopeValue)
        }
        if ($null -ne $ExceptIfSentToMemberOf -and $ExceptIfSentToMemberOf.Count -gt 0) { $ruleParams.Add('ExceptIfSentToMemberOf', $ExceptIfSentToMemberOf) }
        if ($null -ne $ExceptIfSubjectContainsWords -and $ExceptIfSubjectContainsWords.Count -gt 0) {
            $ruleParams.Add('ExceptIfSubjectContainsWords', $ExceptIfSubjectContainsWords)
        }
        if ($null -ne $ExceptIfSubjectMatchesPatterns -and $ExceptIfSubjectMatchesPatterns.Count -gt 0) {
            $ruleParams.Add('ExceptIfSubjectMatchesPatterns', $ExceptIfSubjectMatchesPatterns)
        }
        if ($null -ne $ExceptIfSubjectOrBodyContainsWords -and $ExceptIfSubjectOrBodyContainsWords.Count -gt 0) {
            $ruleParams.Add('ExceptIfSubjectOrBodyContainsWords', $ExceptIfSubjectOrBodyContainsWords)
        }
        if ($null -ne $ExceptIfSubjectOrBodyMatchesPatterns -and $ExceptIfSubjectOrBodyMatchesPatterns.Count -gt 0) {
            $ruleParams.Add('ExceptIfSubjectOrBodyMatchesPatterns', $ExceptIfSubjectOrBodyMatchesPatterns)
        }
        if ($null -ne $ExceptIfFromAddressContainsWords -and $ExceptIfFromAddressContainsWords.Count -gt 0) {
            $ruleParams.Add('ExceptIfFromAddressContainsWords', $ExceptIfFromAddressContainsWords)
        }
        if ($null -ne $ExceptIfFromAddressMatchesPatterns -and $ExceptIfFromAddressMatchesPatterns.Count -gt 0) {
            $ruleParams.Add('ExceptIfFromAddressMatchesPatterns', $ExceptIfFromAddressMatchesPatterns)
        }
        if ($null -ne $ExceptIfAttachmentContainsWords -and $ExceptIfAttachmentContainsWords.Count -gt 0) {
            $ruleParams.Add('ExceptIfAttachmentContainsWords', $ExceptIfAttachmentContainsWords)
        }
        if ($null -ne $ExceptIfAttachmentMatchesPatterns -and $ExceptIfAttachmentMatchesPatterns.Count -gt 0) {
            $ruleParams.Add('ExceptIfAttachmentMatchesPatterns', $ExceptIfAttachmentMatchesPatterns)
        }
        if ($null -ne $ExceptIfAttachmentExtensionMatchesWords -and $ExceptIfAttachmentExtensionMatchesWords.Count -gt 0) {
            $ruleParams.Add('ExceptIfAttachmentExtensionMatchesWords', $ExceptIfAttachmentExtensionMatchesWords)
        }
        if ($null -ne $ExceptIfAttachmentSizeOver) {
            $ruleParams.Add('ExceptIfAttachmentSizeOver', $ExceptIfAttachmentSizeOver)
        }
        if ($null -ne $ExceptIfMessageSizeOver) { $ruleParams.Add('ExceptIfMessageSizeOver', $ExceptIfMessageSizeOver) }
        if ($null -ne $ExceptIfSCLOver) {
            $exceptSclValue = if ($ExceptIfSCLOver.value) { $ExceptIfSCLOver.value } else { $ExceptIfSCLOver }
            $ruleParams.Add('ExceptIfSCLOver', $exceptSclValue)
        }
        if ($null -ne $ExceptIfWithImportance) {
            $exceptImportanceValue = if ($ExceptIfWithImportance.value) { $ExceptIfWithImportance.value } else { $ExceptIfWithImportance }
            $ruleParams.Add('ExceptIfWithImportance', $exceptImportanceValue)
        }
        if ($null -ne $ExceptIfMessageTypeMatches) {
            $exceptMessageTypeValue = if ($ExceptIfMessageTypeMatches.value) { $ExceptIfMessageTypeMatches.value } else { $ExceptIfMessageTypeMatches }
            $ruleParams.Add('ExceptIfMessageTypeMatches', $exceptMessageTypeValue)
        }
        if ($null -ne $ExceptIfSenderDomainIs -and $ExceptIfSenderDomainIs.Count -gt 0) {
            $ruleParams.Add('ExceptIfSenderDomainIs', $ExceptIfSenderDomainIs)
        }
        if ($null -ne $ExceptIfRecipientDomainIs -and $ExceptIfRecipientDomainIs.Count -gt 0) {
            $ruleParams.Add('ExceptIfRecipientDomainIs', $ExceptIfRecipientDomainIs)
        }
        if ($null -ne $ExceptIfRecipientAddressContainsWords -and $ExceptIfRecipientAddressContainsWords.Count -gt 0) {
            $ruleParams.Add('ExceptIfRecipientAddressContainsWords', $ExceptIfRecipientAddressContainsWords)
        }
        if ($null -ne $ExceptIfRecipientAddressMatchesPatterns -and $ExceptIfRecipientAddressMatchesPatterns.Count -gt 0) {
            $ruleParams.Add('ExceptIfRecipientAddressMatchesPatterns', $ExceptIfRecipientAddressMatchesPatterns)
        }
        if ($null -ne $ExceptIfAnyOfRecipientAddressContainsWords -and $ExceptIfAnyOfRecipientAddressContainsWords.Count -gt 0) {
            $ruleParams.Add('ExceptIfAnyOfRecipientAddressContainsWords', $ExceptIfAnyOfRecipientAddressContainsWords)
        }
        if ($null -ne $ExceptIfAnyOfRecipientAddressMatchesPatterns -and $ExceptIfAnyOfRecipientAddressMatchesPatterns.Count -gt 0) {
            $ruleParams.Add('ExceptIfAnyOfRecipientAddressMatchesPatterns', $ExceptIfAnyOfRecipientAddressMatchesPatterns)
        }
        if ($null -ne $ExceptIfAnyOfToHeader -and $ExceptIfAnyOfToHeader.Count -gt 0) {
            $ruleParams.Add('ExceptIfAnyOfToHeader', $ExceptIfAnyOfToHeader)
        }
        if ($null -ne $ExceptIfAnyOfToHeaderMemberOf -and $ExceptIfAnyOfToHeaderMemberOf.Count -gt 0) {
            $ruleParams.Add('ExceptIfAnyOfToHeaderMemberOf', $ExceptIfAnyOfToHeaderMemberOf)
        }
        if ($null -ne $ExceptIfAnyOfCcHeader -and $ExceptIfAnyOfCcHeader.Count -gt 0) {
            $ruleParams.Add('ExceptIfAnyOfCcHeader', $ExceptIfAnyOfCcHeader)
        }
        if ($null -ne $ExceptIfAnyOfCcHeaderMemberOf -and $ExceptIfAnyOfCcHeaderMemberOf.Count -gt 0) {
            $ruleParams.Add('ExceptIfAnyOfCcHeaderMemberOf', $ExceptIfAnyOfCcHeaderMemberOf)
        }
        if ($null -ne $ExceptIfAnyOfToCcHeader -and $ExceptIfAnyOfToCcHeader.Count -gt 0) {
            $ruleParams.Add('ExceptIfAnyOfToCcHeader', $ExceptIfAnyOfToCcHeader)
        }
        if ($null -ne $ExceptIfAnyOfToCcHeaderMemberOf -and $ExceptIfAnyOfToCcHeaderMemberOf.Count -gt 0) {
            $ruleParams.Add('ExceptIfAnyOfToCcHeaderMemberOf', $ExceptIfAnyOfToCcHeaderMemberOf)
        }
        if ($null -ne $ExceptIfHeaderContainsWords -and $ExceptIfHeaderContainsWords.Count -gt 0 -and $null -ne $ExceptIfHeaderContainsWordsMessageHeader) {
            $ruleParams.Add('ExceptIfHeaderContainsMessageHeader', $ExceptIfHeaderContainsWordsMessageHeader)
            $ruleParams.Add('ExceptIfHeaderContainsWords', $ExceptIfHeaderContainsWords)
        }
        if ($null -ne $ExceptIfHeaderMatchesPatterns -and $ExceptIfHeaderMatchesPatterns.Count -gt 0 -and $null -ne $ExceptIfHeaderMatchesPatternsMessageHeader) {
            $ruleParams.Add('ExceptIfHeaderMatchesMessageHeader', $ExceptIfHeaderMatchesPatternsMessageHeader)
            $ruleParams.Add('ExceptIfHeaderMatchesPatterns', $ExceptIfHeaderMatchesPatterns)
        }
        if ($null -ne $ExceptIfSenderIpRanges -and $ExceptIfSenderIpRanges.Count -gt 0) {
            $ruleParams.Add('ExceptIfSenderIpRanges', $ExceptIfSenderIpRanges)
        }

        if (!$Identity) {
            $ExoRequestParam = @{
                tenantid         = $TenantFilter
                cmdlet           = 'New-TransportRule'
                cmdParams        = $ruleParams
                useSystemMailbox = $true
            }
            $null = New-ExoRequest @ExoRequestParam
            $Results = "Successfully created transport rule '$Name'"
        }
        else {
            $ExoRequestParam = @{
                tenantid         = $TenantFilter
                cmdlet           = 'Set-TransportRule'
                cmdParams        = $ruleParams
                useSystemMailbox = $true
            }
            $ExoRequestState = @{
                tenantid         = $TenantFilter
                cmdlet           = $CmdletState
                cmdParams        = @{ Identity = $Identity }
                useSystemMailbox = $true
            }
            if ($Enabled) {
                $null = New-ExoRequest @ExoRequestState
                $Results = "Successfully $($Enabled) transport rule $($Name)"
            } else {
                $null = New-ExoRequest @ExoRequestParam
                $null = New-ExoRequest @ExoRequestState
                $Results = "Successfully configured transport rule '$Name'"
            }
        }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to configure transport rule '$Name'. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Results -Sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{Results = $Results }
        })
}

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
    $SentTo = $Request.Body.SentTo
    $SentToScope = $Request.Body.SentToScope
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
    $HeaderContainsWords = $Request.Body.HeaderContainsWords
    $HeaderContainsWordsMessageHeader = $Request.Body.HeaderContainsWordsMessageHeader
    $HeaderMatchesPatterns = $Request.Body.HeaderMatchesPatterns
    $HeaderMatchesPatternsMessageHeader = $Request.Body.HeaderMatchesPatternsMessageHeader

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
    $ExceptIfSentTo = $Request.Body.ExceptIfSentTo
    $ExceptIfSentToScope = $Request.Body.ExceptIfSentToScope
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
    $ExceptIfHeaderContainsWords = $Request.Body.ExceptIfHeaderContainsWords
    $ExceptIfHeaderContainsWordsMessageHeader = $Request.Body.ExceptIfHeaderContainsWordsMessageHeader
    $ExceptIfHeaderMatchesPatterns = $Request.Body.ExceptIfHeaderMatchesPatterns
    $ExceptIfHeaderMatchesPatternsMessageHeader = $Request.Body.ExceptIfHeaderMatchesPatternsMessageHeader

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
    $SentTo = Process-ArrayField -Field $SentTo
    $RedirectMessageTo = Process-ArrayField -Field $RedirectMessageTo
    $BlindCopyTo = Process-ArrayField -Field $BlindCopyTo
    $CopyTo = Process-ArrayField -Field $CopyTo
    $ModerateMessageByUser = Process-ArrayField -Field $ModerateMessageByUser
    $ExceptIfFrom = Process-ArrayField -Field $ExceptIfFrom
    $ExceptIfSentTo = Process-ArrayField -Field $ExceptIfSentTo
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
    $ExceptIfHeaderContainsWords = Process-TextArrayField -Field $ExceptIfHeaderContainsWords
    $ExceptIfHeaderMatchesPatterns = Process-TextArrayField -Field $ExceptIfHeaderMatchesPatterns

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
        if ($null -ne $Mode -and $null -ne $Mode.value) { $ruleParams.Add('Mode', $Mode.value) }
        if ($null -ne $SetAuditSeverity -and $null -ne $SetAuditSeverity.value -and $SetAuditSeverity.value -ne '') {
            $ruleParams.Add('SetAuditSeverity', $SetAuditSeverity.value)
        }
        if ($null -ne $StopRuleProcessing) { $ruleParams.Add('StopRuleProcessing', $StopRuleProcessing) }
        if ($null -ne $SenderAddressLocation -and $null -ne $SenderAddressLocation.value) {
            $ruleParams.Add('SenderAddressLocation', $SenderAddressLocation.value)
        }
        if ($null -ne $ActivationDate -and $ActivationDate -ne '') { $ruleParams.Add('ActivationDate', $ActivationDate) }
        if ($null -ne $ExpiryDate -and $ExpiryDate -ne '') { $ruleParams.Add('ExpiryDate', $ExpiryDate) }

        # Condition parameters
        if ($null -ne $From -and $From.Count -gt 0) { $ruleParams.Add('From', $From) }
        if ($null -ne $FromScope -and $null -ne $FromScope.value) { $ruleParams.Add('FromScope', $FromScope.value) }
        if ($null -ne $SentTo -and $SentTo.Count -gt 0) { $ruleParams.Add('SentTo', $SentTo) }
        if ($null -ne $SentToScope -and $null -ne $SentToScope.value) { $ruleParams.Add('SentToScope', $SentToScope.value) }
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
        if ($null -ne $SCLOver -and $null -ne $SCLOver.value) { $ruleParams.Add('SCLOver', $SCLOver.value) }
        if ($null -ne $WithImportance -and $null -ne $WithImportance.value) {
            $ruleParams.Add('WithImportance', $WithImportance.value)
        }
        if ($null -ne $MessageTypeMatches -and $null -ne $MessageTypeMatches.value) {
            $ruleParams.Add('MessageTypeMatches', $MessageTypeMatches.value)
        }
        if ($null -ne $SenderDomainIs -and $SenderDomainIs.Count -gt 0) {
            $ruleParams.Add('SenderDomainIs', $SenderDomainIs)
        }
        if ($null -ne $RecipientDomainIs -and $RecipientDomainIs.Count -gt 0) {
            $ruleParams.Add('RecipientDomainIs', $RecipientDomainIs)
        }
        if ($null -ne $HeaderContainsWords -and $HeaderContainsWords.Count -gt 0 -and $null -ne $HeaderContainsWordsMessageHeader) {
            $ruleParams.Add('HeaderContainsMessageHeader', $HeaderContainsWordsMessageHeader)
            $ruleParams.Add('HeaderContainsWords', $HeaderContainsWords)
        }
        if ($null -ne $HeaderMatchesPatterns -and $HeaderMatchesPatterns.Count -gt 0 -and $null -ne $HeaderMatchesPatternsMessageHeader) {
            $ruleParams.Add('HeaderMatchesMessageHeader', $HeaderMatchesPatternsMessageHeader)
            $ruleParams.Add('HeaderMatchesPatterns', $HeaderMatchesPatterns)
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
        if ($null -ne $SetSCL -and $null -ne $SetSCL.value) { $ruleParams.Add('SetSCL', $SetSCL.value) }
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
            if ($null -ne $ApplyHtmlDisclaimerLocation -and $null -ne $ApplyHtmlDisclaimerLocation.value) {
                $ruleParams.Add('ApplyHtmlDisclaimerLocation', $ApplyHtmlDisclaimerLocation.value)
            }
            if ($null -ne $ApplyHtmlDisclaimerFallbackAction -and $null -ne $ApplyHtmlDisclaimerFallbackAction.value) {
                $ruleParams.Add('ApplyHtmlDisclaimerFallbackAction', $ApplyHtmlDisclaimerFallbackAction.value)
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
        if ($null -ne $ExceptIfFromScope -and $null -ne $ExceptIfFromScope.value) {
            $ruleParams.Add('ExceptIfFromScope', $ExceptIfFromScope.value)
        }
        if ($null -ne $ExceptIfSentTo -and $ExceptIfSentTo.Count -gt 0) { $ruleParams.Add('ExceptIfSentTo', $ExceptIfSentTo) }
        if ($null -ne $ExceptIfSentToScope -and $null -ne $ExceptIfSentToScope.value) {
            $ruleParams.Add('ExceptIfSentToScope', $ExceptIfSentToScope.value)
        }
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
        if ($null -ne $ExceptIfSCLOver -and $null -ne $ExceptIfSCLOver.value) {
            $ruleParams.Add('ExceptIfSCLOver', $ExceptIfSCLOver.value)
        }
        if ($null -ne $ExceptIfWithImportance -and $null -ne $ExceptIfWithImportance.value) {
            $ruleParams.Add('ExceptIfWithImportance', $ExceptIfWithImportance.value)
        }
        if ($null -ne $ExceptIfMessageTypeMatches -and $null -ne $ExceptIfMessageTypeMatches.value) {
            $ruleParams.Add('ExceptIfMessageTypeMatches', $ExceptIfMessageTypeMatches.value)
        }
        if ($null -ne $ExceptIfSenderDomainIs -and $ExceptIfSenderDomainIs.Count -gt 0) {
            $ruleParams.Add('ExceptIfSenderDomainIs', $ExceptIfSenderDomainIs)
        }
        if ($null -ne $ExceptIfRecipientDomainIs -and $ExceptIfRecipientDomainIs.Count -gt 0) {
            $ruleParams.Add('ExceptIfRecipientDomainIs', $ExceptIfRecipientDomainIs)
        }
        if ($null -ne $ExceptIfHeaderContainsWords -and $ExceptIfHeaderContainsWords.Count -gt 0 -and $null -ne $ExceptIfHeaderContainsWordsMessageHeader) {
            $ruleParams.Add('ExceptIfHeaderContainsMessageHeader', $ExceptIfHeaderContainsWordsMessageHeader)
            $ruleParams.Add('ExceptIfHeaderContainsWords', $ExceptIfHeaderContainsWords)
        }
        if ($null -ne $ExceptIfHeaderMatchesPatterns -and $ExceptIfHeaderMatchesPatterns.Count -gt 0 -and $null -ne $ExceptIfHeaderMatchesPatternsMessageHeader) {
            $ruleParams.Add('ExceptIfHeaderMatchesMessageHeader', $ExceptIfHeaderMatchesPatternsMessageHeader)
            $ruleParams.Add('ExceptIfHeaderMatchesPatterns', $ExceptIfHeaderMatchesPatterns)
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

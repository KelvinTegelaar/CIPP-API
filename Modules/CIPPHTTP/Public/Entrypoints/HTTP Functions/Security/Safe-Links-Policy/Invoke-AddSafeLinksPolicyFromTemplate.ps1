Function Invoke-AddSafeLinksPolicyFromTemplate {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.SafeLinks.ReadWrite
    .DESCRIPTION
        This function deploys SafeLinks policies and rules from templates to selected tenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers


    try {
        $RequestBody = $Request.Body

        # Extract tenant IDs from selectedTenants
        $SelectedTenants = $RequestBody.selectedTenants | ForEach-Object { $_.value }
        if ('AllTenants' -in $SelectedTenants) {
            $SelectedTenants = (Get-Tenants).defaultDomainName
        }

        # Extract templates from TemplateList
        $Templates = $RequestBody.TemplateList | ForEach-Object { $_.value }

        if (-not $Templates -or $Templates.Count -eq 0) {
            throw "No templates provided in TemplateList"
        }

        # Helper function to process array fields with cleaner logic
        function ConvertTo-SafeArray {
            param($Field)

            if ($null -eq $Field) { return @() }

            # Handle arrays
            if ($Field -is [array]) {
                return $Field | ForEach-Object {
                    if ($_ -is [string]) { $_ }
                    elseif ($_.value) { $_.value }
                    elseif ($_.userPrincipalName) { $_.userPrincipalName }
                    elseif ($_.id) { $_.id }
                    else { $_.ToString() }
                }
            }

            # Handle single objects
            if ($Field -is [hashtable] -or $Field -is [PSCustomObject]) {
                if ($Field.value) { return @($Field.value) }
                if ($Field.userPrincipalName) { return @($Field.userPrincipalName) }
                if ($Field.id) { return @($Field.id) }
            }

            # Handle strings
            if ($Field -is [string]) { return @($Field) }

            return @($Field)
        }

        function Test-PolicyExists {
            param($TenantFilter, $PolicyName)

            $ExistingPolicies = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-SafeLinksPolicy' -useSystemMailbox $true
            return $ExistingPolicies | Where-Object { $_.Name -eq $PolicyName }
        }

        function Test-RuleExists {
            param($TenantFilter, $RuleName)

            $ExistingRules = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-SafeLinksRule' -useSystemMailbox $true
            return $ExistingRules | Where-Object { $_.Name -eq $RuleName }
        }

        function New-SafeLinksPolicyFromTemplate {
            param($TenantFilter, $Template)

            $PolicyName = $Template.PolicyName
            $RuleName = $Template.RuleName ?? "$($PolicyName)_Rule"

            # Check if policy already exists
            if (Test-PolicyExists -TenantFilter $TenantFilter -PolicyName $PolicyName) {
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Policy '$PolicyName' already exists" -Sev 'Warning'
                return "Policy '$PolicyName' already exists in tenant $TenantFilter"
            }

            # Check if rule already exists
            if (Test-RuleExists -TenantFilter $TenantFilter -RuleName $RuleName) {
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Rule '$RuleName' already exists" -Sev 'Warning'
                return "Rule '$RuleName' already exists in tenant $TenantFilter"
            }

            # Process array fields
            $DoNotRewriteUrls = ConvertTo-SafeArray -Field $Template.DoNotRewriteUrls
            $SentTo = ConvertTo-SafeArray -Field $Template.SentTo
            $SentToMemberOf = ConvertTo-SafeArray -Field $Template.SentToMemberOf
            $RecipientDomainIs = ConvertTo-SafeArray -Field $Template.RecipientDomainIs
            $ExceptIfSentTo = ConvertTo-SafeArray -Field $Template.ExceptIfSentTo
            $ExceptIfSentToMemberOf = ConvertTo-SafeArray -Field $Template.ExceptIfSentToMemberOf
            $ExceptIfRecipientDomainIs = ConvertTo-SafeArray -Field $Template.ExceptIfRecipientDomainIs

            # Create policy parameters
            $PolicyParams = @{ Name = $PolicyName }

            # Policy configuration mapping
            $PolicyMappings = @{
                'EnableSafeLinksForEmail' = 'EnableSafeLinksForEmail'
                'EnableSafeLinksForTeams' = 'EnableSafeLinksForTeams'
                'EnableSafeLinksForOffice' = 'EnableSafeLinksForOffice'
                'TrackClicks' = 'TrackClicks'
                'AllowClickThrough' = 'AllowClickThrough'
                'ScanUrls' = 'ScanUrls'
                'EnableForInternalSenders' = 'EnableForInternalSenders'
                'DeliverMessageAfterScan' = 'DeliverMessageAfterScan'
                'DisableUrlRewrite' = 'DisableUrlRewrite'
                'AdminDisplayName' = 'AdminDisplayName'
                'CustomNotificationText' = 'CustomNotificationText'
                'EnableOrganizationBranding' = 'EnableOrganizationBranding'
            }

            foreach ($templateKey in $PolicyMappings.Keys) {
                if ($null -ne $Template.$templateKey) {
                    $PolicyParams[$PolicyMappings[$templateKey]] = $Template.$templateKey
                }
            }

            if ($DoNotRewriteUrls.Count -gt 0) {
                $PolicyParams['DoNotRewriteUrls'] = $DoNotRewriteUrls
            }

            # Create SafeLinks Policy
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-SafeLinksPolicy' -cmdParams $PolicyParams -useSystemMailbox $true
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Created SafeLinks policy '$PolicyName'" -Sev 'Info'

            # Create rule parameters
            $RuleParams = @{
                Name = $RuleName
                SafeLinksPolicy = $PolicyName
            }

            # Rule configuration mapping
            $RuleMappings = @{
                'Priority' = 'Priority'
                'TemplateDescription' = 'Comments'
            }

            foreach ($templateKey in $RuleMappings.Keys) {
                if ($null -ne $Template.$templateKey) {
                    $RuleParams[$RuleMappings[$templateKey]] = $Template.$templateKey
                }
            }

            # Add array parameters if they have values
            $ArrayMappings = @{
                'SentTo' = $SentTo
                'SentToMemberOf' = $SentToMemberOf
                'RecipientDomainIs' = $RecipientDomainIs
                'ExceptIfSentTo' = $ExceptIfSentTo
                'ExceptIfSentToMemberOf' = $ExceptIfSentToMemberOf
                'ExceptIfRecipientDomainIs' = $ExceptIfRecipientDomainIs
            }

            foreach ($paramName in $ArrayMappings.Keys) {
                if ($ArrayMappings[$paramName].Count -gt 0) {
                    $RuleParams[$paramName] = $ArrayMappings[$paramName]
                }
            }

            # Create SafeLinks Rule
            $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'New-SafeLinksRule' -cmdParams $RuleParams -useSystemMailbox $true
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Created SafeLinks rule '$RuleName'" -Sev 'Info'

            # Handle rule state
            $StateMessage = ""
            if ($null -ne $Template.State) {
                $IsState = switch ($Template.State) {
                    "Enabled" { $true }
                    "Disabled" { $false }
                    $true { $true }
                    $false { $false }
                    default { $null }
                }

                if ($null -ne $IsState) {
                    $Cmdlet = $IsState ? 'Enable-SafeLinksRule' : 'Disable-SafeLinksRule'
                    $null = New-ExoRequest -tenantid $TenantFilter -cmdlet $Cmdlet -cmdParams @{ Identity = $RuleName } -useSystemMailbox $true
                    $StateMessage = " (rule $($IsState ? 'enabled' : 'disabled'))"
                }
            }

            return "Successfully deployed SafeLinks policy '$PolicyName' and rule '$RuleName' to tenant $TenantFilter$StateMessage"
        }

        # Process each tenant and template combination
        $Results = foreach ($TenantFilter in $SelectedTenants) {
            foreach ($Template in $Templates) {
                try {
                    New-SafeLinksPolicyFromTemplate -TenantFilter $TenantFilter -Template $Template
                }
                catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    $ErrorDetail = "Failed to deploy template '$($Template.TemplateName)' to tenant $TenantFilter. Error: $($ErrorMessage.NormalizedError)"
                    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $ErrorDetail -Sev 'Error'
                    $ErrorDetail
                }
            }
        }

        $StatusCode = [HttpStatusCode]::OK
    }
    catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to process template deployment request. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Results -Sev 'Error'
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    # Return response
    return ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Body = @{ Results = $Results }
    })
}

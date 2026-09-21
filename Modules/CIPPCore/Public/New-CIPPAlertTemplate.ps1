function New-CIPPAlertTemplate {
    param(
        [Parameter(Mandatory = $true)]
        $Data,
        [Parameter(Mandatory = $true)]
        $Format,
        $InputObject = 'auditlog',
        $LocationInfo,
        $ActionResults,
        $CIPPURL,
        $Tenant,
        $AuditLogLink,
        $AlertComment,
        $CustomSubject
    )
    $AppName = Get-CIPPMicrosoftFirstPartyApp -AppId "$($data.applicationId)"
    $TemplatePath = Join-Path $env:CIPPRootPath 'Config\TemplateEmail.html'
    $HTMLTemplate = Get-Content $TemplatePath -Raw | Out-String
    $Title = ''
    $IntroText = ''
    $ButtonUrl = ''
    $ButtonText = ''
    $AfterButtonText = ''
    $RuleTable = ''
    $Table = ''
    $LocationInfo = $LocationInfo ?? $Data.CIPPLocationInfo | ConvertFrom-Json -ErrorAction SilentlyContinue | Select-Object * -ExcludeProperty Etag, PartitionKey, TimeStamp
    if ($Data -is [string]) {
        $Data = @{ message = $Data }
    }
    if ($Data -is [array] -and $Data[0] -is [string]) {
        $Data = $Data | ForEach-Object { @{ message = $_ } }
    }
    if ($InputObject -eq 'driftStandard') {
        $Title = "CIPP Alert - Standard Drift Detected for $($Tenant)"
        $DataHTML = ($Data | ConvertTo-Html -Fragment | Out-String).Replace('<table>', ' <table class="table-modern">')
        $IntroText = "<p>You've setup your instance to receive alerts when a tenant is drifting away from your standard. This seems to have happened! We've found the following deviations. </p>$dataHTML"
        $ButtonUrl = "$CIPPURL/tenant/manage/drift?tenantFilter=$($Tenant)&templateId=$($AuditLogLink)"
        $ButtonText = 'Investigate and remediate deviations'
        $AfterButtonText = 'Click the button above to go to the logbook and investigate the deviations. You can also use the standards page to remediate the deviations.'
    }

    if ($InputObject -eq 'baseline') {
        $Alerts = @($Data)
        $DriftAlerts = @($Alerts | Where-Object { $_.Event -eq 'Drift' })
        $RemediatedAlerts = @($Alerts | Where-Object { $_.Event -eq 'Remediated' })
        $ConflictAlerts = @($Alerts | Where-Object { $_.Event -eq 'Conflict' })

        $Title = if ($Alerts.Count -eq 1) {
            switch ($Alerts[0].Event) {
                'Remediated' { "$($Tenant) - Baseline: fixed automatically - $($Alerts[0].Label)" }
                'Conflict' { "$($Tenant) - Baseline conflict: $($Alerts[0].Label)" }
                default { "$($Tenant) - Baseline change detected: $($Alerts[0].Label)" }
            }
        } else {
            $TitleParts = [System.Collections.Generic.List[string]]::new()
            if ($DriftAlerts.Count -gt 0) { $TitleParts.Add("$($DriftAlerts.Count) need$(if ($DriftAlerts.Count -eq 1) { 's' }) review") }
            if ($RemediatedAlerts.Count -gt 0) { $TitleParts.Add("$($RemediatedAlerts.Count) fixed automatically") }
            if ($ConflictAlerts.Count -gt 0) { $TitleParts.Add("$($ConflictAlerts.Count) in conflict") }
            "$($Tenant) - Baseline: $($TitleParts -join ', ')"
        }

        $Encode = { param($Value) [System.Net.WebUtility]::HtmlEncode("$Value") }
        $MutedStyle = 'color:#6b7280;font-size:13px'

        # Status is the one thing every reader scans for, so it carries color: red needs a
        # decision, green is already handled, amber cannot run.
        $StatusCell = @{
            'Drift'      = '<strong style="color:#b42318">Needs review</strong>'
            'Remediated' = '<strong style="color:#067647">Fixed automatically</strong>'
            'Conflict'   = '<strong style="color:#b54708">Conflict</strong>'
        }
        $SummaryHTML = '<table class="table-modern"><tr><th>Standard</th><th>Status</th></tr>'
        foreach ($Alert in $Alerts) {
            $BaselineNote = "$($Alert.Baseline)$(if ($Alert.Stage) { " · stage $($Alert.Stage)" })"
            $SummaryHTML += ('<tr><td><strong>{0}</strong><br /><span style="{1}">{2}</span></td><td>{3}</td></tr>' -f `
                (& $Encode $Alert.Label), $MutedStyle, (& $Encode $BaselineNote), ($StatusCell[[string]$Alert.Event] ?? (& $Encode $Alert.Event)))
        }
        $SummaryHTML += '</table>'
        $IntroText = "<p>You've set your baseline to alert when a tenant moves away from it. Here is what changed on <strong>$(& $Encode $Tenant)</strong>:</p>$SummaryHTML"

        if ($RemediatedAlerts.Count -gt 0) {
            $IntroText += "<p>CIPP has already put the automatically fixed standard$(if ($RemediatedAlerts.Count -ne 1) { 's' }) back to the agreed value - those need no action.</p>"
        }
        $FormatDiffValue = {
            param($Value)
            if ($null -eq $Value -or "$Value" -eq '') { return '(not set)' }
            if ($Value -is [bool]) { return $(if ($Value) { 'On' } else { 'Off' }) }
            $Text = "$Value"
            if ($Text.Length -gt 120) { $Text = "$($Text.Substring(0, 117))..." }
            & $Encode $Text
        }
        $DetailAlerts = @($DriftAlerts + $ConflictAlerts)
        $DetailShown = 0
        foreach ($Alert in $DetailAlerts) {
            if ($DetailShown -eq 0) {
                $IntroText += '<h2 style="margin-bottom:0">What needs your attention</h2>'
            }
            if ($DetailShown -ge 6) {
                $IntroText += "<p>...and $($DetailAlerts.Count - $DetailShown) more - the alignment page shows every difference.</p>"
                break
            }
            $IntroText += "<h3 style=`"margin-bottom:2px`">$(& $Encode $Alert.Label)</h3>"
            if (![string]::IsNullOrWhiteSpace($Alert.Description)) {
                $IntroText += "<p style=`"$MutedStyle;margin:2px 0 8px 0`">$(& $Encode $Alert.Description)</p>"
            }
            if ($Alert.Event -eq 'Conflict') {
                $IntroText += "<p>Two baselines configure this standard with different settings ($(& $Encode (@($Alert.ConflictWith) -join ' and '))). CIPP cannot pick a side, so nothing runs for it until one of them changes.</p>"
                $DetailShown++
                continue
            }
            $Differences = @($Alert.Differences)
            if ($Differences.Count -gt 0) {
                $DiffHTML = '<table class="table-modern"><tr><th>Setting</th><th>Should be</th><th>Is now</th></tr>'
                foreach ($Difference in ($Differences | Select-Object -First 8)) {
                    $DiffHTML += ('<tr><td>{0}</td><td><strong>{1}</strong></td><td>{2}</td></tr>' -f `
                        (& $Encode $Difference.Property), (& $FormatDiffValue $Difference.ExpectedValue), (& $FormatDiffValue $Difference.ReceivedValue))
                }
                $DiffHTML += '</table>'
                $IntroText += $DiffHTML
                if ($Differences.Count -gt 8) {
                    $IntroText += "<p>...and $($Differences.Count - 8) more difference$(if (($Differences.Count - 8) -ne 1) { 's' }) on this standard.</p>"
                }
            } else {
                $IntroText += '<p>This standard no longer matches its agreed configuration.</p>'
            }
            $DetailShown++
        }

        $ButtonUrl = "$CIPPURL/tenant/baselines/alignment?tenantFilter=$($Tenant)"
        $ButtonText = 'Review baseline alignment'
        $AfterButtonText = '<p>From the alignment page you can remediate a deviation, accept it as an agreed exception with a reason, or inspect every value that differs.</p>'
    }
    if ($InputObject -eq 'sherwebmig') {
        $DataHTML = ($Data | ConvertTo-Html -Fragment | Out-String).Replace('<table>', ' <table class="table-modern">')
        $IntroText = "<p>The following licenses have not yet been found at Sherweb, and are expiring within 7 days:</p>$dataHTML"
        if ($data.SherwebMig -like '*buy*') {
            $introText = "<p>The following licenses have not yet been found at Sherweb, and are expiring within 7 days. We have started the process to automatically buy these licenses:</p>$dataHTML"
        }
    }
    if ($InputObject -eq 'sherwebmigfailcancel') {
        $DataHTML = ($Data | ConvertTo-Html -Fragment | Out-String).Replace('<table>', ' <table class="table-modern">')
        $IntroText = "<p>The following licenses have not been cancelled due to an API error at the old provider:</p>$dataHTML"
    }
    if ($InputObject -eq 'sherwebmigBuyFail') {
        $DataHTML = ($Data | ConvertTo-Html -Fragment | Out-String).Replace('<table>', ' <table class="table-modern">')
        $IntroText = "<p>The following licenses have not been bought as we could not find a correctly matching license. Please login and buy the license:</p>$dataHTML"
    }
    if ($InputObject -eq 'table') {
        #data can be a array of strings or a string, if it is, we need to convert it to an object so it shows up nicely, that object will have one header: message.

        $DataHTML = ($Data | Select-Object * -ExcludeProperty Etag, PartitionKey, TimeStamp | ConvertTo-Html -Fragment | Out-String).Replace('<table>', ' <table class="table-modern">')
        $IntroText = "<p>You've configured CIPP to send you alerts based on the logbook. The following alerts match your configured rules</p>$dataHTML"

        # Add alert comment if provided
        if ($AlertComment) {
            $IntroText = "$IntroText<div style='background-color: #f8f9fa; border-left: 4px solid #007bff; padding: 15px; margin: 15px 0;'><h4 style='margin-top: 0; color: #007bff;'>Alert Information</h4><p style='margin-bottom: 0;'>$AlertComment</p></div>"
        }

        $ButtonUrl = "$CIPPURL/cipp/logs"
        $ButtonText = 'Check logbook information'
    }
    if ($InputObject -eq 'standards') {
        $DataHTML = foreach ($object in $data) {
            "<p>For the standard $($object.standardName) we've detected the following:</p> <li>$($object.message)</li>"
            if ($object.object) {
                $StandardObject = $object.object | ConvertFrom-Json
                $StandardObject = $StandardObject | Select-Object * -ExcludeProperty Etag, PartitionKey, TimeStamp
                if ($StandardObject.compare) {
                    '<p>The following differences have been detected:</p>'
                    ($StandardObject.compare | ConvertTo-Html -Fragment | Out-String).Replace('<table>', ' <table class="table-modern">')
                } else {
                    ($StandardObject | ConvertTo-Html -Fragment -As List | Out-String).Replace('<table>', ' <table class="table-modern">')
                }
            }

        }
        $IntroText = "<p>You're receiving this email because you've set your standards to alert when they are out of sync with your expected baseline.</p>$dataHTML"
        $ButtonUrl = "$CIPPURL/standards/list-standards"
        $ButtonText = 'Check Standards configuration'
    }
    if ($InputObject -eq 'customScript') {
        # $Data is an array of custom-test alert records (one per failing test for this tenant).
        $Alerts = @($Data)
        $Count = $Alerts.Count
        $Title = if ($Count -eq 1) {
            "$($Tenant) - Custom test '$($Alerts[0].ScriptName)' returned status '$($Alerts[0].Status)'"
        } else {
            "$($Tenant) - $Count custom tests need attention"
        }

        $SummaryRows = foreach ($Alert in $Alerts) {
            [PSCustomObject]@{
                Test   = $Alert.ScriptName
                Status = $Alert.Status
                Risk   = if ($Alert.Risk) { $Alert.Risk } else { 'Medium' }
            }
        }
        $SummaryHTML = ($SummaryRows | ConvertTo-Html -Fragment | Out-String).Replace('<table>', ' <table class="table-modern">')
        $IntroText = "<p>You're receiving this because you enabled failure alerts for one or more custom tests. The following custom test(s) on tenant <strong>$($Tenant)</strong> need attention:</p>$SummaryHTML"

        foreach ($Alert in $Alerts) {
            $IntroText += "<h3>$($Alert.ScriptName) — $($Alert.Status)</h3>"
            if (![string]::IsNullOrWhiteSpace($Alert.ErrorMessage)) {
                $IntroText += "<p>The test failed to execute: $($Alert.ErrorMessage)</p>"
            } elseif (![string]::IsNullOrWhiteSpace($Alert.ResultMarkdown)) {
                $IntroText += "<div style='background-color: #f8f9fa; border-left: 4px solid #007bff; padding: 15px; margin: 15px 0; white-space: pre-wrap;'>$($Alert.ResultMarkdown)</div>"
            } elseif ($Alert.FailedRows) {
                # Normalize string rows to objects so ConvertTo-Html renders a message column
                # instead of the string's Length property.
                $Rows = foreach ($r in @($Alert.FailedRows)) { if ($r -is [string]) { [PSCustomObject]@{ message = $r } } else { $r } }
                $DetailHTML = ($Rows | Select-Object * -ExcludeProperty Etag, PartitionKey, TimeStamp | ConvertTo-Html -Fragment | Out-String).Replace('<table>', ' <table class="table-modern">')
                $IntroText += "<p>Results:</p>$DetailHTML"
            }
        }
        $ButtonUrl = "$CIPPURL/tools/custom-tests"
        $ButtonText = 'View custom test results'
    }
    if ($InputObject -eq 'auditlog') {
        $ButtonUrl = "$CIPPURL/identity/administration/users/user/bec?userId=$($data.ObjectId)&tenantFilter=$Tenant"
        $ButtonText = 'User Management'
        $AfterButtonText = '<p>If this is incorrect, use the user management screen to block the user and revoke the sessions</p>'
        switch ($Data.Operation) {
            'New-InboxRule' {
                # Test if the rule is a forwarding or redirect rule
                $ForwardProperties = @('ForwardTo', 'RedirectTo')
                foreach ($ForwardProperty in $ForwardProperties) {
                    if ($Data.PSobject.Properties.Name -contains $ForwardProperty) {
                        $FoundForwarding = $true
                    }
                }
                if ($FoundForwarding -eq $true) {
                    $Title = "$($Tenant) - New forwarding or redirect Rule Detected for $($data.UserId)"
                } else {
                    $Title = "$($Tenant) - New Rule Detected for $($data.UserId)"
                }
                $RuleTable = ($Data.CIPPParameters | ConvertFrom-Json | ConvertTo-Html -Fragment | Out-String).Replace('<table>', ' <table class="table-modern">')

                $IntroText = "<p>A new rule has been created for the user $($data.UserId). You should check if this rule is not malicious. The rule information can be found in the table below.</p>$RuleTable"
                if ($ActionResults) { $IntroText = $IntroText + "<p>Based on the rule, the following actions have been taken: $($ActionResults -join '<br/>' )</p>" }
                if ($LocationInfo) {
                    $LocationTable = ($LocationInfo | ConvertTo-Html -Fragment -As List | Out-String).Replace('<table>', ' <table class="table-modern">')
                    $IntroText = $IntroText + "<p>The (potential) location information for this IP is as follows:</p>$LocationTable"
                }
                $ButtonUrl = "$CIPPURL/identity/administration/users/user/bec?userId=$($data.UserId)&tenantFilter=$Tenant"
                $ButtonText = 'Start BEC Investigation'
                $AfterButtonText = '<p>If you believe this is a suspect rule, you can click the button above to start the investigation.</p>'
            }
            'Set-InboxRule' {
                $Title = "$($Tenant) - Rule Edit Detected for $($data.UserId)"
                $RuleTable = ($Data.CIPPParameters | ConvertFrom-Json | ConvertTo-Html -Fragment | Out-String).Replace('<table>', ' <table class="table-modern">')
                $IntroText = "<p>A rule has been edited for the user $($data.UserId). You should check if this rule is not malicious. The rule information can be found in the table below.</p>$RuleTable"
                if ($ActionResults) { $IntroText = $IntroText + "<p>Based on the rule, the following actions have been taken: $($ActionResults -join '<br/>' )</p>" }
                if ($LocationInfo) {
                    $LocationTable = ($LocationInfo | ConvertTo-Html -Fragment -As List | Out-String).Replace('<table>', ' <table class="table-modern">')
                    $IntroText = $IntroText + "<p>The (potential) location information for this IP is as follows:</p>$LocationTable"
                }
                $ButtonUrl = "$CIPPURL/identity/administration/users/user/bec?userId=$($data.UserId)&tenantFilter=$Tenant"
                $ButtonText = 'Start BEC Investigation'
                $AfterButtonText = '<p>If you believe this is a suspect rule, you can click the button above to start the investigation.</p>'
            }
            'Add member to role.' {
                $Title = "$($Tenant) - Role change detected for $($data.ObjectId)"
                $Table = ($data.CIPPModifiedProperties | ConvertFrom-Json | ConvertTo-Html -Fragment | Out-String).Replace('<table>', ' <table class="table-modern">')
                $IntroText = "<p>$($data.UserId) has added $($data.ObjectId) to the $(($data.'Role.DisplayName')) role. The information about the role can be found in the table below.</p>$Table"
                if ($ActionResults) { $IntroText = $IntroText + "<p>Based on the rule, the following actions have been taken: $($ActionResults -join '<br/>' )</p>" }
                if ($LocationInfo) {
                    $LocationTable = ($LocationInfo | ConvertTo-Html -Fragment -As List | Out-String).Replace('<table>', ' <table class="table-modern">')
                    $IntroText = $IntroText + "<p>The (potential) location information for this IP is as follows:</p>$LocationTable"
                }
                $ButtonUrl = "$CIPPURL/identity/administration/roles?customerId=$($data.OrganizationId)"
                $ButtonText = 'Role Management'
                $AfterButtonText = '<p>If this role is incorrect, or you need more information, use the button to jump to the Role Management page.</p>'

            }
            'Disable account.' {
                $Title = "$($Tenant) - $($data.ObjectId) has been disabled"
                $IntroText = "$($data.ObjectId) has been disabled by $($data.UserId)."
                if ($ActionResults) { $IntroText = $IntroText + "<p>Based on the rule, the following actions have been taken: $($ActionResults -join '<br/>' )</p>" }
                if ($LocationInfo) {
                    $LocationTable = ($LocationInfo | ConvertTo-Html -Fragment -As List | Out-String).Replace('<table>', ' <table class="table-modern">')
                    $IntroText = $IntroText + "<p>The (potential) location information for this IP is as follows:</p>$LocationTable"
                }
                $ButtonUrl = "$CIPPURL/identity/administration/users?customerId=$($data.OrganizationId)"
                $ButtonText = 'User Management'
                $AfterButtonText = '<p>If this is incorrect, use the user management screen to unblock the users sign-in</p>'
            }
            'Enable account.' {
                $Title = "$($Tenant) - $($data.ObjectId) has been enabled"
                $IntroText = "$($data.ObjectId) has been enabled by $($data.UserId)."
                $ButtonUrl = "$CIPPURL/identity/administration/users?customerId=$($data.OrganizationId)"
                if ($ActionResults) { $IntroText = $IntroText + "<p>Based on the rule, the following actions have been taken: $($ActionResults -join '<br/>' )</p>" }
                if ($LocationInfo) {
                    $LocationTable = ($LocationInfo | ConvertTo-Html -Fragment -As List | Out-String).Replace('<table>', ' <table class="table-modern">')
                    $IntroText = $IntroText + "<p>The (potential) location information for this IP is as follows:</p>$LocationTable"
                }
                $ButtonText = 'User Management'
                $AfterButtonText = '<p>If this is incorrect, use the user management screen to unblock the users sign-in</p>'
            }
            'Update StsRefreshTokenValidFrom Timestamp.' {
                $Title = "$($Tenant) - $($data.ObjectId) has had all sessions revoked"
                $IntroText = "$($data.ObjectId) has had their sessions revoked by $($data.UserId)."
                $ButtonUrl = "$CIPPURL/identity/administration/users?customerId=$($data.OrganizationId)"
                if ($ActionResults) { $IntroText = $IntroText + "<p>Based on the rule, the following actions have been taken: $($ActionResults -join '<br/>' )</p>" }
                if ($LocationInfo) {
                    $LocationTable = ($LocationInfo | ConvertTo-Html -Fragment -As List | Out-String).Replace('<table>', ' <table class="table-modern">')
                    $IntroText = $IntroText + "<p>The (potential) location information for this IP is as follows:</p>$LocationTable"
                }
                $ButtonText = 'User Management'
                $AfterButtonText = '<p>If this is incorrect, use the user management screen to unblock the users sign-in</p>'
            }
            'Disable Strong Authentication.' {
                $Title = "$($Tenant) - $($data.ObjectId) has been MFA disabled"
                $IntroText = "$($data.ObjectId) MFA has been disabled by $($data.UserId)."
                if ($ActionResults) { $IntroText = $IntroText + "<p>Based on the rule, the following actions have been taken: $($ActionResults -join '<br/>' )</p>" }
                if ($LocationInfo) {
                    $LocationTable = ($LocationInfo | ConvertTo-Html -Fragment -As List | Out-String).Replace('<table>', ' <table class="table-modern">')
                    $IntroText = $IntroText + "<p>The (potential) location information for this IP is as follows:</p>$LocationTable"
                }
                $ButtonUrl = "$CIPPURL/identity/administration/users?customerId=$($data.OrganizationId)"
                $ButtonText = 'User Management'
                $AfterButtonText = '<p>If this is incorrect, use the user management screen to reenable MFA</p>'
            }
            'Remove Member from a role.' {
                $Title = "$($Tenant) - Role change detected for $($data.ObjectId)"
                $Table = ($data.CIPPModifiedProperties | ConvertFrom-Json | ConvertTo-Html -Fragment | Out-String).Replace('<table>', ' <table class="table-modern">')
                $IntroText = "<p>$($data.UserId) has removed $($data.ObjectId) to the $(($data.ModifiedProperties | Where-Object -Property Name -EQ 'Role.DisplayName').NewValue) role. The information about the role can be found in the table below.</p>$Table"
                if ($ActionResults) { $IntroText = $IntroText + "<p>Based on the rule, the following actions have been taken: $($ActionResults -join '<br/>' )</p>" }
                if ($LocationInfo) {
                    $LocationTable = ($LocationInfo | ConvertTo-Html -Fragment -As List | Out-String).Replace('<table>', ' <table class="table-modern">')
                    $IntroText = $IntroText + "<p>The (potential) location information for this IP is as follows:</p>$LocationTable"
                }
                $ButtonUrl = "$CIPPURL/identity/administration/roles?customerId=$($data.OrganizationId)"
                $ButtonText = 'Role Management'
                $AfterButtonText = '<p>If this role change is incorrect, or you need more information, use the button to jump to the Role Management page.</p>'

            }

            'Reset user password.' {
                $Title = "$($Tenant) - $($data.ObjectId) has had their password reset"
                $IntroText = "$($data.ObjectId) has had their password reset by $($data.userId)."
                if ($ActionResults) { $IntroText = $IntroText + "<p>Based on the rule, the following actions have been taken: $($ActionResults -join '<br/>' )</p>" }
                if ($LocationInfo) {
                    $LocationTable = ($LocationInfo | ConvertTo-Html -Fragment -As List | Out-String).Replace('<table>', ' <table class="table-modern">')
                    $IntroText = $IntroText + "<p>The (potential) location information for this IP is as follows:</p>$LocationTable"
                }
                $ButtonUrl = "$CIPPURL/identity/administration/users?customerId=$($data.OrganizationId)"
                $ButtonText = 'User Management'
                $AfterButtonText = '<p>If this is incorrect, use the user management screen to unblock the users sign-in</p>'

            }
            'Add service principal.' {
                if (-not $AppName) { $AppName = $data.ApplicationId }
                $Title = "$($Tenant) - Service Principal $($data.ObjectId) has been added."
                $Table = ($data.ModifiedProperties | ConvertTo-Html -Fragment | Out-String).Replace('<table>', ' <table class="table-modern">')
                if ($ActionResults) { $IntroText = $IntroText + "<p>Based on the rule, the following actions have been taken: $($ActionResults -join '<br/>' )</p>" }
                if ($LocationInfo) {
                    $LocationTable = ($LocationInfo | ConvertTo-Html -Fragment -As List | Out-String).Replace('<table>', ' <table class="table-modern">')
                    $IntroText = $IntroText + "<p>The (potential) location information for this IP is as follows:</p>$LocationTable"
                }
                $IntroText = "$($data.ObjectId) has been added by $($data.UserId)."
                $ButtonUrl = "$CIPPURL/tenant/administration/applications/enterprise-apps?tenantFilter=$Tenant"
                $ButtonText = 'Enterprise Apps'
            }
            'Remove service principal.' {
                if (-not $AppName) { $AppName = $data.ApplicationId }
                $Title = "$($Tenant) - Service Principal $($data.ObjectId) has been removed."
                $Table = ($data.CIPPModifiedProperties | ConvertFrom-Json | ConvertTo-Html -Fragment | Out-String).Replace('<table>', ' <table class="table-modern">')
                if ($ActionResults) { $IntroText = $IntroText + "<p>Based on the rule, the following actions have been taken: $($ActionResults -join '<br/>' )</p>" }
                if ($LocationInfo) {
                    $LocationTable = ($LocationInfo | ConvertTo-Html -Fragment -As List | Out-String).Replace('<table>', ' <table class="table-modern">')
                    $IntroText = $IntroText + "<p>The (potential) location information for this IP is as follows:</p>$LocationTable"
                }
                $IntroText = "$($data.ObjectId) has been removed by $($data.UserId)."
                $ButtonUrl = "$CIPPURL/tenant/administration/applications/enterprise-apps?tenantFilter=$Tenant"
                $ButtonText = 'Enterprise Apps'
            }
            'UserLoggedIn' {
                $Table = ($data | ConvertTo-Html -Fragment -As List | Out-String).Replace('<table>', ' <table class="table-modern">')
                if (-not $AppName) { $AppName = $data.ApplicationId }
                $Title = "$($Tenant) - a user has logged on from a location you've set up to receive alerts for."
                $IntroText = "$($data.UserId) ($($data.Userkey)) has logged on from IP $($data.ClientIP) to the application $($Appname). According to our database this is located in $($LocationInfo.CountryOrRegion) - $($LocationInfo.City). <br/><br> You have set up alerts to be notified when this happens. See the table below for more info.$Table"
                if ($ActionResults) { $IntroText = $IntroText + "<p>Based on the rule, the following actions have been taken: $($ActionResults -join '<br/>' )</p>" }
                if ($LocationInfo) {
                    $LocationTable = ($LocationInfo | ConvertTo-Html -Fragment -As List | Out-String).Replace('<table>', ' <table class="table-modern">')
                    $IntroText = $IntroText + "<p>The (potential) location information for this IP is as follows:</p>$LocationTable"
                }
                $ButtonUrl = "$CIPPURL/identity/administration/users/user/bec?userId=$($data.Userkey)&tenantFilter=$Tenant"
                $ButtonText = 'User Management'
                $AfterButtonText = '<p>If this is incorrect, use the user management screen to block the user and revoke the sessions</p>'
            }
            default {
                $Title = 'A custom alert has occured'
                $Table = ($data | ConvertTo-Html -Fragment -As List | Out-String).Replace('<table>', ' <table class="table-modern">')
                $IntroText = "<p>You have setup CIPP to send you a custom alert for the audit events that follow this filter: $($data.cippclause) </p>$Table"
                if ($ActionResults) { $IntroText = $IntroText + "<p>Based on the rule, the following actions have been taken: $($ActionResults -join '<br/>' )</p>" }
                if ($LocationInfo) {
                    $LocationTable = ($LocationInfo | ConvertTo-Html -Fragment -As List | Out-String).Replace('<table>', ' <table class="table-modern">')
                    $IntroText = $IntroText + "<p>The (potential) location information for this IP is as follows:</p>$LocationTable"
                }
                $ButtonUrl = "$CIPPURL/identity/administration/users?tenantFilter=$Tenant"
                $ButtonText = 'User Management'
            }
        }

        # Append a deep-link to the source audit event so technicians can jump straight from
        # the ticket to the raw record in CIPP for forensics, regardless of which action page
        # the primary button takes them to.
        if (![string]::IsNullOrWhiteSpace($AuditLogLink)) {
            $AfterButtonText = "$AfterButtonText<p>For forensics, <a href=`"$AuditLogLink`">view the source audit event in CIPP</a>.</p>"
        }
    }

    if (![string]::IsNullOrWhiteSpace($CustomSubject)) {
        # Resolve %property% tokens against the alert data so subjects like
        # '%username% - suspicious login' carry the actual value. Unknown tokens stay as-is.
        # $Data is a single object for audit logs but an array of rows for logbook alerts,
        # so only resolve when every row agrees - a multi-user alert has no one username.
        $ResolvedSubject = [regex]::Replace($CustomSubject, '%(\w+)%', {
                param($Match)
                $PropertyName = switch ($Match.Groups[1].Value) {
                    'username' { 'UserId' }
                    'tenant' { return $Tenant }
                    default { $Match.Groups[1].Value }
                }
                $Values = foreach ($Row in @($Data)) {
                    if ($null -eq $Row) { continue }
                    if ($Row -is [System.Collections.IDictionary]) {
                        $Row[$PropertyName]
                    } else {
                        ($Row.PSObject.Properties | Where-Object { $_.Name -ieq $PropertyName } | Select-Object -First 1).Value
                    }
                }
                $Distinct = @($Values | Where-Object { ![string]::IsNullOrWhiteSpace("$_") } | ForEach-Object { "$_" } | Select-Object -Unique)
                if ($Distinct.Count -eq 1) { $Distinct[0] } else { $Match.Value }
            })
        $Title = '{0} - {1}' -f $Tenant, $ResolvedSubject
    }

    if ($Format -eq 'html') {
        $AssembledHtml = $HTMLTemplate -f $Title, $IntroText, $ButtonUrl, $ButtonText, $AfterButtonText, $AuditLogLink
        $AssembledHtml = $AssembledHtml -replace '\r\n', '' -replace '\n', ''
        return [pscustomobject]@{
            title       = $Title
            htmlcontent = $AssembledHtml
        }
    } elseif ($Format -eq 'psa') {
        # PSA ticket bodies get a bare fragment instead of the full email template: the
        # template styles its tables with a <style> block and classes, which Halo stores
        # but never applies, so the tables lose their borders and padding (#4243).
        $PsaContent = $IntroText
        if ($ButtonUrl -and $ButtonText) {
            $PsaContent = "$PsaContent<p><a href=`"$ButtonUrl`">$ButtonText</a></p>"
        }
        if ($AfterButtonText) {
            $PsaContent = "$PsaContent$AfterButtonText"
        }
        if ($AuditLogLink) {
            $PsaContent = "$PsaContent<p><a href=`"$AuditLogLink`">View the audit log entry in CIPP</a></p>"
        }
        return [pscustomobject]@{
            title       = $Title
            htmlcontent = (ConvertTo-PSAHtml -Html $PsaContent)
        }
    } elseif ($Format -eq 'json') {
        if ($InputObject -eq 'auditlog') {
            return [pscustomobject]@{
                title = $Title
                html  = $IntroText
                data  = $data
            }
        }
        return [pscustomobject]@{
            title        = $Title
            buttonurl    = $ButtonUrl
            buttontext   = $ButtonText
            auditlog     = $AuditLogLink
            alertcomment = $AlertComment
        }
    }
}

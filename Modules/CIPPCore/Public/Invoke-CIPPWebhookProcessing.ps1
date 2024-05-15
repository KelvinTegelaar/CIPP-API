function Invoke-CippWebhookProcessing {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $Data,
        $Resource,
        $Operations,
        $CIPPPURL,
        $APIName = 'Process webhook',
        $ExecutingUser
    )

    <# $ExtendedPropertiesIgnoreList = @(
        'OAuth2:Authorize'
        'OAuth2:Token'
        'SAS:EndAuth'
        'SAS:ProcessAuth'
        'Login:reprocess'
    ) #>
    Write-Host "Received data. Our Action List is $($data.CIPPAction)"

    $ActionList = ($data.CIPPAction | ConvertFrom-Json -ErrorAction SilentlyContinue).value
    $ActionResults = foreach ($action in $ActionList) {
        Write-Host "this is our action: $($action | ConvertTo-Json -Depth 15 -Compress))"
        switch ($action) {
            'disableUser' {
                Set-CIPPSignInState -TenantFilter $TenantFilter -User $data.UserId -AccountEnabled $false -APIName 'Alert Engine' -ExecutingUser 'Alert Engine'
            }
            'becremediate' {
                $username = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($data.UserId)" -tenantid $TenantFilter).UserPrincipalName
                Set-CIPPResetPassword -userid $username -tenantFilter $TenantFilter -APIName 'Alert Engine' -ExecutingUser 'Alert Engine'
                Set-CIPPSignInState -userid $username -AccountEnabled $false -tenantFilter $TenantFilter -APIName 'Alert Engine' -ExecutingUser 'Alert Engine'
                Revoke-CIPPSessions -userid $username -username $username -ExecutingUser 'Alert Engine' -APIName 'Alert Engine' -tenantFilter $TenantFilter
                $RuleDisabled = 0
                New-ExoRequest -anchor $username -tenantid $TenantFilter -cmdlet 'get-inboxrule' -cmdParams @{Mailbox = $username } | ForEach-Object {
                    $null = New-ExoRequest -anchor $username -tenantid $TenantFilter -cmdlet 'Disable-InboxRule' -cmdParams @{Confirm = $false; Identity = $_.Identity }
                    "Disabled Inbox Rule $($_.Identity) for $username"
                    $RuleDisabled ++
                }
                if ($RuleDisabled) {
                    "Disabled $RuleDisabled Inbox Rules for $username"
                } else {
                    "No Inbox Rules found for $username. We have not disabled any rules."
                }
                "Completed BEC Remediate for $username"
                Write-LogMessage -API 'BECRemediate' -tenant $tenantfilter -message "Executed Remediation for  $username" -sev 'Info'
            }
            'cippcommand' {
                $CommandSplat = @{}
                $action.parameters.psobject.properties | ForEach-Object { $CommandSplat.Add($_.name, $_.value) }
                if ($CommandSplat['userid']) { $CommandSplat['userid'] = $data.userid }
                if ($CommandSplat['tenantfilter']) { $CommandSplat['tenantfilter'] = $tenantfilter }
                if ($CommandSplat['tenant']) { $CommandSplat['tenant'] = $tenantfilter }
                if ($CommandSplat['user']) { $CommandSplat['user'] = $data.userid }
                if ($CommandSplat['username']) { $CommandSplat['username'] = $data.userid }
                & $action.command.value @CommandSplat
            }
        }
    }
    Write-Host 'Going to create the content'
    foreach ($action in $ActionList ) {
        switch ($action) {
            'generatemail' {
                Write-Host 'Going to create the email'
                $GenerateEmail = New-CIPPAlertTemplate -format 'html' -data $Data -ActionResults $ActionResults
                Write-Host 'Going to send the mail'
                Send-CIPPAlert -Type 'email' -Title $GenerateEmail.title -HTMLContent $GenerateEmail.htmlcontent -TenantFilter $TenantFilter
                Write-Host 'email should be sent'
            }
            'generatePSA' {
                $GenerateEmail = New-CIPPAlertTemplate -format 'html' -data $Data -ActionResults $ActionResults
                Send-CIPPAlert -Type 'psa' -Title $GenerateEmail.title -HTMLContent $GenerateEmail.htmlcontent -TenantFilter $TenantFilter
            }
            'generateWebhook' {
                Write-Host 'Generating the webhook content'
                $LocationInfo = $Data.CIPPLocationInfo | ConvertFrom-Json -ErrorAction SilentlyContinue
                $GenerateJSON = New-CIPPAlertTemplate -format 'json' -data $Data -ActionResults $ActionResults
                $JsonContent = @{
                    Title                 = $GenerateJSON.Title
                    ActionUrl             = $GenerateJSON.ButtonUrl
                    RawData               = $Data
                    IP                    = $data.ClientIP
                    PotentialLocationInfo = $LocationInfo
                    ActionsTaken          = [string]($ActionResults | ConvertTo-Json -Depth 15 -Compress)
                } | ConvertTo-Json -Depth 15 -Compress
                Write-Host 'Sending Webhook Content'

                Send-CIPPAlert -Type 'webhook' -Title $GenerateJSON.Title -JSONContent $JsonContent -TenantFilter $TenantFilter
            }
        }
    }
}


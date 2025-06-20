function Invoke-CippWebhookProcessing {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $Data,
        $Resource,
        $Operations,
        $CIPPURL,
        $APIName = 'Process webhook',
        $Headers
    )

    $AuditLogTable = Get-CIPPTable -TableName 'AuditLogs'
    $AuditLog = Get-CIPPAzDataTableEntity @AuditLogTable -Filter "PartitionKey eq '$TenantFilter' and RowKey eq '$($Data.Id)'"

    if ($AuditLog) {
        Write-Host "Audit Log already exists for $($Data.Id). Skipping processing."
        return
    }

    $Tenant = Get-Tenants -IncludeErrors | Where-Object { $_.defaultDomainName -eq $TenantFilter }
    Write-Host "Received data. Our Action List is $($data.CIPPAction)"

    $ActionList = ($data.CIPPAction | ConvertFrom-Json -ErrorAction SilentlyContinue).value
    $ActionResults = foreach ($action in $ActionList) {
        Write-Host "this is our action: $($action | ConvertTo-Json -Depth 15 -Compress)"
        switch ($action) {
            'disableUser' {
                Set-CIPPSignInState -TenantFilter $TenantFilter -User $data.UserId -AccountEnabled $false -APIName 'Alert Engine' -Headers 'Alert Engine'
            }
            'becremediate' {
                $Username = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($data.UserId)" -tenantid $TenantFilter).UserPrincipalName
                Set-CIPPResetPassword -UserID $Username -tenantFilter $TenantFilter -APIName 'Alert Engine' -Headers 'Alert Engine'
                Set-CIPPSignInState -userid $Username -AccountEnabled $false -tenantFilter $TenantFilter -APIName 'Alert Engine' -Headers 'Alert Engine'
                Revoke-CIPPSessions -userid $Username -username $Username -Headers 'Alert Engine' -APIName 'Alert Engine' -tenantFilter $TenantFilter
                $RuleDisabled = 0
                $RuleFailed = 0
                New-ExoRequest -anchor $Username -tenantid $TenantFilter -cmdlet 'Get-InboxRule' -cmdParams @{Mailbox = $Username; IncludeHidden = $true } | Where-Object { $_.Name -ne 'Junk E-Mail Rule' -and $_.Name -notlike 'Microsoft.Exchange.OOF.*' } | ForEach-Object {
                    try {
                        Set-CIPPMailboxRule -Username $Username -TenantFilter $TenantFilter -RuleId $_.Identity -RuleName $_.Name -Disable -APIName 'Alert Engine' -Headers 'Alert Engine'
                        $RuleDisabled++
                    } catch {
                        $_.Exception.Message
                        $RuleFailed++
                    }
                }
                if ($RuleDisabled -gt 0) {
                    "Disabled $RuleDisabled Inbox Rules for $Username"
                } else {
                    "No Inbox Rules found for $Username. We have not disabled any rules."
                }
                if ($RuleFailed -gt 0) {
                    "Failed to disable $RuleFailed Inbox Rules for $Username"
                }
                "Completed BEC Remediate for $Username"
                Write-LogMessage -API 'BECRemediate' -tenant $TenantFilter -message "Executed Remediation for $Username" -sev 'Info'
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

    # Save audit log entry to table
    $LocationInfo = $Data.CIPPLocationInfo | ConvertFrom-Json -ErrorAction SilentlyContinue
    $AuditRecord = $Data.AuditRecord | ConvertFrom-Json -ErrorAction SilentlyContinue
    $GenerateJSON = New-CIPPAlertTemplate -format 'json' -data $Data -ActionResults $ActionResults -CIPPURL $CIPPURL
    $JsonContent = @{
        Title                 = $GenerateJSON.Title
        ActionUrl             = $GenerateJSON.ButtonUrl
        ActionText            = $GenerateJSON.ButtonText
        RawData               = $Data
        IP                    = $data.ClientIP
        PotentialLocationInfo = $LocationInfo
        ActionsTaken          = $ActionResults
        AuditRecord           = $AuditRecord
    } | ConvertTo-Json -Depth 15 -Compress

    $CIPPAlert = @{
        Type         = 'table'
        Title        = $GenerateJSON.Title
        JSONContent  = $JsonContent
        TenantFilter = $TenantFilter
        TableName    = 'AuditLogs'
        RowKey       = $Data.Id
    }
    $LogId = Send-CIPPAlert @CIPPAlert

    $AuditLogLink = '{0}/tenant/administration/audit-logs/log?logId={1}&tenantFilter={2}' -f $CIPPURL, $LogId, $Tenant.defaultDomainName
    $GenerateEmail = New-CIPPAlertTemplate -format 'html' -data $Data -ActionResults $ActionResults -CIPPURL $CIPPURL -Tenant $Tenant.defaultDomainName -AuditLogLink $AuditLogLink

    Write-Host 'Going to create the content'
    foreach ($action in $ActionList ) {
        switch ($action) {
            'generatemail' {
                $CIPPAlert = @{
                    Type         = 'email'
                    Title        = $GenerateEmail.title
                    HTMLContent  = $GenerateEmail.htmlcontent
                    TenantFilter = $TenantFilter
                }
                Write-Host 'Going to send the mail'
                Send-CIPPAlert @CIPPAlert
                Write-Host 'email should be sent'
            }
            'generatePSA' {
                $CIPPAlert = @{
                    Type         = 'psa'
                    Title        = $GenerateEmail.title
                    HTMLContent  = $GenerateEmail.htmlcontent
                    TenantFilter = $TenantFilter
                }
                Send-CIPPAlert @CIPPAlert
            }
            'generateWebhook' {
                $CippAlert = @{
                    Type         = 'webhook'
                    Title        = $GenerateJSON.Title
                    JSONContent  = $JsonContent
                    TenantFilter = $TenantFilter
                }
                Write-Host 'Sending Webhook Content'
                Send-CIPPAlert @CippAlert
            }
        }
    }
}


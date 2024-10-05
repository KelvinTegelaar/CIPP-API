function Invoke-CippWebhookProcessing {
    [CmdletBinding()]
    param (
        $TenantFilter,
        $Data,
        $Resource,
        $Operations,
        $CIPPURL,
        $APIName = 'Process webhook',
        $ExecutingUser
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
                Set-CIPPSignInState -TenantFilter $TenantFilter -User $data.UserId -AccountEnabled $false -APIName 'Alert Engine' -ExecutingUser 'Alert Engine'
            }
            'becremediate' {
                $username = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($data.UserId)" -tenantid $TenantFilter).UserPrincipalName
                Set-CIPPResetPassword -UserID $username -tenantFilter $TenantFilter -APIName 'Alert Engine' -ExecutingUser 'Alert Engine'
                Set-CIPPSignInState -userid $username -AccountEnabled $false -tenantFilter $TenantFilter -APIName 'Alert Engine' -ExecutingUser 'Alert Engine'
                Revoke-CIPPSessions -userid $username -username $username -ExecutingUser 'Alert Engine' -APIName 'Alert Engine' -tenantFilter $TenantFilter
                $RuleDisabled = 0
                New-ExoRequest -anchor $username -tenantid $TenantFilter -cmdlet 'Get-InboxRule' -cmdParams @{Mailbox = $username; IncludeHidden = $true } | Where-Object { $_.Name -ne 'Junk E-Mail Rule' -and $_.Name -notlike 'Microsoft.Exchange.OOF.*' } | ForEach-Object {
                    $null = New-ExoRequest -anchor $username -tenantid $TenantFilter -cmdlet 'Disable-InboxRule' -cmdParams @{Confirm = $false; Identity = $_.Identity }
                    "Disabled Inbox Rule $($_.Identity) for $username"
                    $RuleDisabled++
                }
                if ($RuleDisabled) {
                    "Disabled $RuleDisabled Inbox Rules for $username"
                } else {
                    "No Inbox Rules found for $username. We have not disabled any rules."
                }
                "Completed BEC Remediate for $username"
                Write-LogMessage -API 'BECRemediate' -tenant $tenantfilter -message "Executed Remediation for $username" -sev 'Info'
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

    $AuditLogLink = '{0}/tenant/administration/audit-logs?customerId={1}&logId={2}' -f $CIPPURL, $Tenant.customerId, $LogId
    $GenerateEmail = New-CIPPAlertTemplate -format 'html' -data $Data -ActionResults $ActionResults -CIPPURL $CIPPURL

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


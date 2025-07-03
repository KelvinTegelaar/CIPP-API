function Invoke-CippWebhookProcessing {
    <#
    .SYNOPSIS
    Process webhook data and execute automated remediation actions
    
    .DESCRIPTION
    Processes incoming webhook data, executes automated remediation actions, and generates alerts and notifications
    
    .FUNCTIONALITY
        Webhook Processing
    .ROLE
        Webhook.Process
        
    .NOTES
    Group: Webhooks
    Summary: Process Webhook
    Description: Processes webhook data from various sources, executes automated remediation actions including user disable, BEC remediation, and custom commands, then generates alerts and notifications
    Tags: Webhooks,Automation,Remediation,Alerts
    Parameter: TenantFilter (string) - Target tenant identifier
    Parameter: Data (object) - Webhook data containing user information and action details
    Parameter: Resource (string) - Resource type being processed
    Parameter: Operations (array) - Array of operations to perform
    Parameter: CIPPURL (string) - Base URL for CIPP application
    Parameter: APIName (string) - Name of the API being called (default: 'Process webhook')
    Parameter: Headers (object) - Request headers
    Response: No direct response - processes webhook data and generates alerts
    Response: Actions performed based on CIPPAction:
    Response: - disableUser: Disables the user account
    Response: - becremediate: Performs BEC remediation including password reset, account disable, session revocation, and inbox rule disable
    Response: - cippcommand: Executes custom CIPP commands with parameter substitution
    Response: - generatemail: Sends email alert with HTML content
    Response: - generatePSA: Sends PSA alert with HTML content
    Response: - generateWebhook: Sends webhook alert with JSON content
    Example: The function processes webhook data and performs actions like:
    Example: - Disabling compromised user accounts
    Example: - Resetting passwords and revoking sessions
    Example: - Disabling suspicious inbox rules
    Example: - Generating and sending alerts via email, PSA, or webhook
    #>
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
    Write-Host "Received data. Our Action List is $($Data.CIPPAction)"

    $ActionList = ($Data.CIPPAction | ConvertFrom-Json -ErrorAction SilentlyContinue).value
    $ActionResults = foreach ($action in $ActionList) {
        Write-Host "this is our action: $($action | ConvertTo-Json -Depth 15 -Compress)"
        switch ($action) {
            'disableUser' {
                try {
                    Set-CIPPSignInState -TenantFilter $TenantFilter -User $Data.UserId -AccountEnabled $false -APIName 'Alert Engine' -Headers 'Alert Engine'
                } catch {
                    Write-Host "Failed to disable user $($Data.UserId)`: $($_.Exception.Message)"
                }
            }
            'becremediate' {
                $Username = (New-GraphGetRequest -uri "https://graph.microsoft.com/beta/users/$($Data.UserId)" -tenantid $TenantFilter).UserPrincipalName
                try {
                    Set-CIPPResetPassword -UserID $Username -tenantFilter $TenantFilter -APIName 'Alert Engine' -Headers 'Alert Engine'
                } catch {
                    Write-Host "Failed to reset password for $Username`: $($_.Exception.Message)"
                }
                try {
                    Set-CIPPSignInState -userid $Username -AccountEnabled $false -tenantFilter $TenantFilter -APIName 'Alert Engine' -Headers 'Alert Engine'
                } catch {
                    Write-Host "Failed to disable sign-in for $Username`: $($_.Exception.Message)"
                }
                try {
                    Revoke-CIPPSessions -userid $Username -username $Username -Headers 'Alert Engine' -APIName 'Alert Engine' -tenantFilter $TenantFilter
                } catch {
                    Write-Host "Failed to revoke sessions for $Username`: $($_.Exception.Message)"
                }
                $RuleDisabled = 0
                New-ExoRequest -anchor $Username -tenantid $TenantFilter -cmdlet 'Get-InboxRule' -cmdParams @{Mailbox = $Username; IncludeHidden = $true } | Where-Object { $_.Name -ne 'Junk E-Mail Rule' -and $_.Name -notlike 'Microsoft.Exchange.OOF.*' } | ForEach-Object {
                    $null = New-ExoRequest -anchor $Username -tenantid $TenantFilter -cmdlet 'Disable-InboxRule' -cmdParams @{Confirm = $false; Identity = $_.Identity }
                    "Disabled Inbox Rule $($_.Identity) for $Username"
                    $RuleDisabled++
                }
                if ($RuleDisabled) {
                    "Disabled $RuleDisabled Inbox Rules for $Username"
                } else {
                    "No Inbox Rules found for $Username. We have not disabled any rules."
                }
                "Completed BEC Remediate for $Username"
                Write-LogMessage -API 'BECRemediate' -tenant $tenantfilter -message "Executed Remediation for $Username" -sev 'Info'
            }
            'cippcommand' {
                $CommandSplat = @{}
                $action.parameters.psobject.properties | ForEach-Object { $CommandSplat.Add($_.name, $_.value) }
                if ($CommandSplat['userid']) { $CommandSplat['userid'] = $Data.UserId }
                if ($CommandSplat['tenantfilter']) { $CommandSplat['tenantfilter'] = $TenantFilter }
                if ($CommandSplat['tenant']) { $CommandSplat['tenant'] = $TenantFilter }
                if ($CommandSplat['user']) { $CommandSplat['user'] = $Data.UserId }
                if ($CommandSplat['username']) { $CommandSplat['username'] = $Data.UserId }
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
        IP                    = $Data.ClientIP
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


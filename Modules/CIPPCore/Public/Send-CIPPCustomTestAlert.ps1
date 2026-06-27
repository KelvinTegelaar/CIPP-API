function Send-CIPPCustomTestAlert {
    <#
    .SYNOPSIS
        Ship an aggregated notification for one or more custom script test results for a tenant.

    .DESCRIPTION
        Builds a single email/PSA HTML body (via New-CIPPAlertTemplate) and a single webhook
        JSON payload covering all alert-worthy custom test results for a tenant, then ships them
        through Send-CIPPAlert for the email, webhook and PSA channels. Each channel self-gates
        inside Send-CIPPAlert on the global CippNotifications configuration, so channels that
        aren't configured are simply skipped.

        This is the "post all the tests" shipping action — Invoke-CIPPTestCollection collects the
        alert records emitted by Invoke-CippTestCustomScripts across every enabled script for a
        tenant and calls this once after the suite has run, so a tenant receives a single
        notification per run rather than one per failing script.

        Routing (recipients / webhook URL / PSA) comes entirely from the instance-wide
        CippNotifications config, the same source used by the audit-log alert engine.

    .PARAMETER TenantFilter
        The tenant the tests ran against.

    .PARAMETER Alerts
        One or more custom-test alert records (as emitted by Invoke-CippTestCustomScripts). Each
        record carries TestId, ScriptGuid, ScriptName, Status, Risk, Pillar, FailedRows,
        ResultMarkdown and (on execution failure) ErrorMessage.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        $Alerts
    )

    try {
        $Alerts = @($Alerts)
        if ($Alerts.Count -eq 0) { return }

        # UseStandardizedSchema flag comes from the global CippNotifications config, matching
        # how Push-SchedulerCIPPNotifications resolves it for webhook delivery.
        $ConfigTable = Get-CIPPTable -TableName SchedulerConfig
        $Config = [pscustomobject](Get-CIPPAzDataTableEntity @ConfigTable -Filter "RowKey eq 'CippNotifications' and PartitionKey eq 'CippNotifications'")

        # CIPP URL for the email button link.
        $CippConfigTable = Get-CippTable -tablename Config
        $CippConfig = Get-CIPPAzDataTableEntity @CippConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'"
        $CIPPURL = 'https://{0}' -f $CippConfig.Value

        # Email / PSA HTML
        $Template = New-CIPPAlertTemplate -Format 'html' -InputObject 'customScript' -Data $Alerts -CIPPURL $CIPPURL -Tenant $TenantFilter
        $Title = $Template.title

        # Email — Send-CIPPAlert no-ops if no notification email is configured.
        $null = Send-CIPPAlert -Type 'email' -Title $Title -HTMLContent $Template.htmlcontent -TenantFilter $TenantFilter -APIName 'CustomTests'

        # PSA — Send-CIPPAlert no-ops unless config.sendtoIntegration is set.
        $null = Send-CIPPAlert -Type 'psa' -Title $Title -HTMLContent $Template.htmlcontent -TenantFilter $TenantFilter -APIName 'CustomTests'

        # Webhook — hand-built payload, Send-CIPPAlert no-ops if no webhook is configured.
        $WebhookData = [PSCustomObject]@{
            Title      = $Title
            Tenant     = $TenantFilter
            AlertCount = $Alerts.Count
            Tests      = @($Alerts | ForEach-Object {
                    [PSCustomObject]@{
                        TestId         = $_.TestId
                        ScriptGuid     = $_.ScriptGuid
                        ScriptName     = $_.ScriptName
                        Status         = $_.Status
                        Risk           = if ($_.Risk) { $_.Risk } else { 'Medium' }
                        Pillar         = $_.Pillar
                        Category       = 'Custom Script'
                        FailedRowCount = @($_.FailedRows).Count
                        Results        = $_.FailedRows
                        ResultMarkdown = $_.ResultMarkdown
                        ErrorMessage   = $_.ErrorMessage
                    }
                })
        } | ConvertTo-Json -Depth 10 -Compress

        $null = Send-CIPPAlert -Type 'webhook' -Title $Title -JSONContent $WebhookData -TenantFilter $TenantFilter `
            -APIName 'CustomTests' -SchemaSource 'Custom Test Notification' -InvokingCommand 'Invoke-CippTestCustomScripts' `
            -UseStandardizedSchema:$([boolean]$Config.UseStandardizedSchema)
    } catch {
        $Err = Get-CippException -Exception $_
        Write-LogMessage -API 'CustomTests' -tenant $TenantFilter -message "Failed to send custom test alerts: $($Err.NormalizedError)" -sev Error -LogData $Err
    }
}

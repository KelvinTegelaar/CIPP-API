# Pester tests for Invoke-CippWebhookProcessing - the alert dispatch and dedupe step.
#
# This runs once per MATCHED audit record, so anything it does per call is multiplied by the
# number of alerting records across every tenant in a fan-out. The tenant resolution it needs is
# identical for every record of a tenant, and Get-Tenants has no in-process cache of its own -
# it reads the tenants table twice, filters through the pipeline and sorts the whole list. These
# tests pin that it is resolved once per tenant rather than once per record, and that the memo
# never serves one tenant's entry to another.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Webhooks/Invoke-CIPPWebhookProcessing.ps1'

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Context, $Filter, $Property, $First) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force, $OperationType) }
    function Get-Tenants { param([switch]$IncludeErrors, [switch]$IncludeAll) }
    function New-CIPPAlertTemplate { param($format, $data, $ActionResults, $CIPPURL, $AlertComment, $CustomSubject, $Tenant, $AuditLogLink) }
    function Send-CIPPAlert { param($Type, $Title, $HTMLContent, $JSONContent, $TenantFilter, $APIName, $SchemaSource, $InvokingCommand, $AffectedUser) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }

    function New-WebhookData {
        param([string]$Id = 'rec-1')
        [pscustomobject]@{
            Id                = $Id
            CIPPAction        = $null   # no actions: keeps these tests on the dispatch path only
            CIPPLocationInfo  = $null
            AuditRecord       = '{}'
            CIPPCustomSubject = $null
            ClientIP          = '20.190.144.12'
            ObjectId          = $null
            UserId            = 'user1@contoso.com'
            Userkey           = $null
        }
    }

    . $FunctionPath
}

Describe 'Invoke-CippWebhookProcessing' {

    BeforeEach {
        # The memo is per tenant and deliberately outlives a call, so it has to be cleared between
        # tests or the second test onwards would never invoke its own Get-Tenants mock.
        $script:WebhookTenantCache = @{}
        $script:TenantCalls = 0
        $script:ClaimedRows = [System.Collections.Generic.List[object]]::new()
        $script:ExistingAuditLog = @()

        Mock -CommandName Get-CIPPTable -MockWith { param($TableName) @{ Context = "ctx:$TableName" } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $script:ExistingAuditLog }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith {
            param($TableName, $Context, $Entity, [switch]$Force, $OperationType)
            $script:ClaimedRows.Add($Entity)
        }
        Mock -CommandName Get-Tenants -MockWith {
            $script:TenantCalls++
            @(
                [pscustomobject]@{ defaultDomainName = 'contoso.com'; customerId = 'cid-contoso' }
                [pscustomobject]@{ defaultDomainName = 'fabrikam.com'; customerId = 'cid-fabrikam' }
            )
        }
        Mock -CommandName New-CIPPAlertTemplate -MockWith {
            # One 'Title' key serves both $GenerateJSON.Title and $GenerateEmail.title - property
            # access is case-insensitive, and a hash literal rejects the pair as duplicates.
            [pscustomobject]@{
                Title = 'alert'; ButtonUrl = 'https://example.invalid'; ButtonText = 'open'
                htmlcontent = '<p>alert</p>'
            }
        }
        Mock -CommandName Send-CIPPAlert -MockWith { }
        Mock -CommandName Write-LogMessage -MockWith { }
    }

    Context 'tenant resolution memo' {

        It 'resolves the tenant once across many records for the same tenant' {
            foreach ($i in 1..25) {
                Invoke-CippWebhookProcessing -TenantFilter 'contoso.com' -Data (New-WebhookData -Id "rec-$i") -CIPPURL 'https://cipp.invalid'
            }
            $script:TenantCalls | Should -Be 1
        }

        It 'resolves each tenant separately' {
            # Serving one tenant's entry to another would put the wrong domain into the alert
            # title, body and audit-log link.
            Invoke-CippWebhookProcessing -TenantFilter 'contoso.com' -Data (New-WebhookData -Id 'rec-1') -CIPPURL 'https://cipp.invalid'
            Invoke-CippWebhookProcessing -TenantFilter 'fabrikam.com' -Data (New-WebhookData -Id 'rec-2') -CIPPURL 'https://cipp.invalid'
            $script:TenantCalls | Should -Be 2
            $script:WebhookTenantCache['contoso.com'].Tenant.defaultDomainName | Should -Be 'contoso.com'
            $script:WebhookTenantCache['fabrikam.com'].Tenant.defaultDomainName | Should -Be 'fabrikam.com'
        }

        It 're-resolves once the entry has expired' {
            Invoke-CippWebhookProcessing -TenantFilter 'contoso.com' -Data (New-WebhookData -Id 'rec-1') -CIPPURL 'https://cipp.invalid'
            $script:WebhookTenantCache['contoso.com'].Expires = [datetime]::UtcNow.AddMinutes(-1)
            Invoke-CippWebhookProcessing -TenantFilter 'contoso.com' -Data (New-WebhookData -Id 'rec-2') -CIPPURL 'https://cipp.invalid'
            $script:TenantCalls | Should -Be 2
        }

        It 'caches a miss so an unknown tenant is not re-queried per record' {
            foreach ($i in 1..10) {
                Invoke-CippWebhookProcessing -TenantFilter 'unknown.com' -Data (New-WebhookData -Id "rec-$i") -CIPPURL 'https://cipp.invalid'
            }
            $script:TenantCalls | Should -Be 1
            $script:WebhookTenantCache['unknown.com'].Tenant | Should -BeNullOrEmpty
        }

        It 'drops expired entries rather than growing per tenant seen' {
            Invoke-CippWebhookProcessing -TenantFilter 'contoso.com' -Data (New-WebhookData -Id 'rec-1') -CIPPURL 'https://cipp.invalid'
            $script:WebhookTenantCache['contoso.com'].Expires = [datetime]::UtcNow.AddMinutes(-1)
            Invoke-CippWebhookProcessing -TenantFilter 'fabrikam.com' -Data (New-WebhookData -Id 'rec-2') -CIPPURL 'https://cipp.invalid'
            $script:WebhookTenantCache.Keys | Should -Not -Contain 'contoso.com'
            $script:WebhookTenantCache.Keys | Should -Contain 'fabrikam.com'
        }
    }

    Context 'dedupe' {

        It 'skips a record whose claim is refused' {
            # The claim is an Insert without -Force, so a conflict IS the duplicate check. A record
            # already claimed - by another worker or an earlier run - fails here and is dropped.
            Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { throw 'The specified entity already exists.' }
            Invoke-CippWebhookProcessing -TenantFilter 'contoso.com' -Data (New-WebhookData -Id 'rec-1') -CIPPURL 'https://cipp.invalid'
            # Returns before resolving the tenant, so a duplicate costs one failed insert and no more.
            $script:TenantCalls | Should -Be 0
            Should -Invoke Send-CIPPAlert -Times 0 -Exactly
        }

        It 'claims the event before dispatching' {
            Invoke-CippWebhookProcessing -TenantFilter 'contoso.com' -Data (New-WebhookData -Id 'rec-1') -CIPPURL 'https://cipp.invalid'
            @($script:ClaimedRows)[0].RowKey | Should -Be 'rec-1'
            @($script:ClaimedRows)[0].Title | Should -Be 'Processing'
        }

        It 'does not read the table before claiming' {
            # The read that used to precede the claim answered the same question a round trip
            # earlier and could not make it safer - a row can still appear between the two. It cost
            # one extra table read per matched record, 28% of the processing stage under load.
            Invoke-CippWebhookProcessing -TenantFilter 'contoso.com' -Data (New-WebhookData -Id 'rec-1') -CIPPURL 'https://cipp.invalid'
            Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly
        }
    }

    Context 'storing the audit log row' {

        It 'writes the row itself when no accumulator is supplied' {
            Invoke-CippWebhookProcessing -TenantFilter 'contoso.com' -Data (New-WebhookData -Id 'rec-1') -CIPPURL 'https://cipp.invalid'
            # Claim plus the completed row.
            $script:ClaimedRows.Count | Should -Be 2
            (@($script:ClaimedRows)[-1]).RowKey | Should -Be 'rec-1'
            (@($script:ClaimedRows)[-1]).Data | Should -Not -BeNullOrEmpty
        }

        It 'queues the row instead of writing it when an accumulator is supplied' {
            $Pending = [System.Collections.Generic.List[object]]::new()
            Invoke-CippWebhookProcessing -TenantFilter 'contoso.com' -Data (New-WebhookData -Id 'rec-1') `
                -CIPPURL 'https://cipp.invalid' -PendingAuditLogWrites $Pending
            $Pending.Count | Should -Be 1
            $Pending[0].RowKey | Should -Be 'rec-1'
            $Pending[0].PartitionKey | Should -Be 'contoso.com'
            # Only the claim was written directly.
            $script:ClaimedRows.Count | Should -Be 1
            (@($script:ClaimedRows)[0]).Title | Should -Be 'Processing'
        }

        It 'dispatches the alert before storing the row' {
            # This ordering is the whole point. Storing first meant a crash between the write and
            # the send left a complete-looking row for an alert nobody received - and the claim row
            # makes a retry skip it, so it is lost silently. Sending first means a crash there
            # leaves the alert delivered and only the stored copy missing.
            $script:Sequence = [System.Collections.Generic.List[string]]::new()
            Mock -CommandName Add-CIPPAzDataTableEntity -MockWith {
                param($TableName, $Context, $Entity, [switch]$Force, $OperationType)
                $script:Sequence.Add($(if ($Entity.Title -eq 'Processing') { 'claim' } else { 'store' }))
                $script:ClaimedRows.Add($Entity)
            }
            Mock -CommandName Send-CIPPAlert -MockWith { $script:Sequence.Add('send') }

            $Data = New-WebhookData -Id 'rec-1'
            $Data.CIPPAction = (ConvertTo-Json -Compress -InputObject @(@{ label = 'Send Webhook'; value = 'generateWebhook' }))
            Invoke-CippWebhookProcessing -TenantFilter 'contoso.com' -Data $Data -CIPPURL 'https://cipp.invalid'

            ($script:Sequence -join ',') | Should -Be 'claim,send,store'
        }
    }

    Context 'alert template rendering' {

        It 'renders the email body only when an action asks for it' {
            # Two renders per alert where one was needed: the html body was built for every matched
            # record regardless of whether any rule wanted an email.
            $Data = New-WebhookData -Id 'rec-1'
            $Data.CIPPAction = (ConvertTo-Json -Compress -InputObject @(@{ label = 'Send Webhook'; value = 'generateWebhook' }))
            Invoke-CippWebhookProcessing -TenantFilter 'contoso.com' -Data $Data -CIPPURL 'https://cipp.invalid'
            Should -Invoke New-CIPPAlertTemplate -Times 1 -Exactly -ParameterFilter { $format -eq 'json' }
            Should -Invoke New-CIPPAlertTemplate -Times 0 -Exactly -ParameterFilter { $format -eq 'html' }
        }

        It 'still renders the email body when generatemail is requested' {
            $Data = New-WebhookData -Id 'rec-1'
            $Data.CIPPAction = (ConvertTo-Json -Compress -InputObject @(@{ label = 'Send Mail'; value = 'generatemail' }))
            Invoke-CippWebhookProcessing -TenantFilter 'contoso.com' -Data $Data -CIPPURL 'https://cipp.invalid'
            Should -Invoke New-CIPPAlertTemplate -Times 1 -Exactly -ParameterFilter { $format -eq 'html' }
            Should -Invoke Send-CIPPAlert -Times 1 -Exactly -ParameterFilter { $Type -eq 'email' }
        }
    }
}

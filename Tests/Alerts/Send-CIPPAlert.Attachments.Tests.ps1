# Pester tests for email attachments in Send-CIPPAlert.
# Graph sendMail rejects a request body over 4MB, so a scheduled report with a large PDF or raw data
# file failed to send at all. Attachments that don't fit are uploaded to blob storage and linked from the
# body instead; if that upload fails they are omitted and the mail still goes out.

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $BackendRoot 'Modules/CIPPCore/Public/Send-CIPPAlert.ps1'

    function Get-CIPPTable { param([string]$TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property, $First) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, $Tenant, [switch]$EscapeForJson) }
    function New-GraphPostRequest { param($uri, $tenantid, $NoAuthCheck, $type, $body) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData, $headers) }
    function Get-CippException { param($Exception) }
    function New-CIPPReportAttachmentLink { param($Name, $ContentBytes, $ContentType) }

    . $FunctionPath

    function Get-TestAttachment([string]$Name, [int]$Base64Length) {
        @{ Name = $Name; ContentType = 'application/octet-stream'; ContentBytes = 'A' * $Base64Length }
    }

    function Send-TestMail($Attachments) {
        $null = Send-CIPPAlert -Type 'email' -Title 'Report' -HTMLContent '<p>body</p>' -TenantFilter 'contoso.onmicrosoft.com' -Attachments $Attachments
        ($script:SentBody | ConvertFrom-Json).message
    }
}

Describe 'Send-CIPPAlert - email attachment size' {
    BeforeEach {
        $script:SentBody = $null
        Mock -CommandName Get-CIPPTable -MockWith { @{} }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { @{ email = 'alerts@contoso.com' } }
        Mock -CommandName Get-CIPPTextReplacement -MockWith { param($TenantFilter, $Text) $Text }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName New-GraphPostRequest -MockWith { param($uri, $tenantid, $NoAuthCheck, $type, $body) $script:SentBody = $body }
        Mock -CommandName New-CIPPReportAttachmentLink -MockWith { param($Name) "https://store.example/report-attachments/x/$($Name)?sig=a&se=b" }
    }

    It 'attaches everything when it fits' {
        $Message = Send-TestMail @((Get-TestAttachment 'report.pdf' 1000), (Get-TestAttachment 'data.csv' 1000))

        @($Message.attachments.name) | Should -Be @('report.pdf', 'data.csv')
    }

    It 'links an attachment that would push the request over 4MB and attaches the rest' {
        $Message = Send-TestMail @((Get-TestAttachment 'report.pdf' 3MB), (Get-TestAttachment 'data.csv' 1MB), (Get-TestAttachment 'small.csv' 1000))

        @($Message.attachments.name) | Should -Be @('report.pdf', 'small.csv')
        Should -Invoke New-CIPPReportAttachmentLink -Times 1 -Exactly -ParameterFilter { $Name -eq 'data.csv' }
        $Message.body.content | Should -BeLike '<p>body</p>*too large*<a href="https://store.example/report-attachments/x/data.csv?sig=a&amp;se=b">data.csv</a>*'
        [System.Text.Encoding]::UTF8.GetByteCount($script:SentBody) | Should -BeLessThan 4MB
    }

    It 'links every attachment when none fit' {
        $Message = Send-TestMail @((Get-TestAttachment 'report.pdf' 5MB))

        Should -Invoke New-GraphPostRequest -Times 1 -Exactly
        $Message.PSObject.Properties.Name | Should -Not -Contain 'attachments'
        $Message.body.content | Should -BeLike '*>report.pdf</a>*'
    }

    It 'omits the attachment and still sends when the upload fails' {
        Mock -CommandName New-CIPPReportAttachmentLink -MockWith { throw 'storage down' }
        $Message = Send-TestMail @((Get-TestAttachment 'report.pdf' 5MB))

        Should -Invoke New-GraphPostRequest -Times 1 -Exactly
        $Message.body.content | Should -Be '<p>body</p>'
        Should -Invoke Write-LogMessage -ParameterFilter { $message -like '*report.pdf*storage down*' }
    }
}

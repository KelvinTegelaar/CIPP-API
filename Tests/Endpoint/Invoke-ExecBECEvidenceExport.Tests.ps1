BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    function New-CIPPBecEvidencePackage { param($TenantFilter, $CaseId, $PdfBase64, $PdfSummaryBase64, $Headers, $APIName) }
    function Set-CippBecCaseContext { param($CaseId) }
    function Write-LogMessage { param($message, $tenant, $API, $tenantId, $headers, $user, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = [string]$Exception.Exception.Message } }
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecBECEvidenceExport.ps1' | Select-Object -First 1
    . $FunctionPath.FullName

    function New-Request {
        param([hashtable]$Body)
        [pscustomobject]@{
            Params  = [pscustomobject]@{ CIPPEndpoint = 'ExecBECEvidenceExport' }
            Headers = [pscustomobject]@{ 'x-ms-client-principal' = 'x' }
            Query   = $null
            Body    = [pscustomobject]$Body
        }
    }
    # 3 KB of deterministic bytes standing in for the ZIP the package builder returns
    $script:ZipBytes = [byte[]]@(0x50, 0x4B, 0x03, 0x04; 1..3068 | ForEach-Object { $_ % 256 })
    $script:Package = [pscustomobject]@{ CaseId = 'BEC-1'; Bytes = $script:ZipBytes.Length; FileCount = 5; ZipBytes = $script:ZipBytes }
}

Describe 'Invoke-ExecBECEvidenceExport' {
    BeforeEach {
        Mock New-CIPPBecEvidencePackage { $script:Package }
        Mock Set-CippBecCaseContext { }
        Mock Write-LogMessage { }
    }

    It 'builds the package for the case and hands the ZIP back base64-encoded with its size and file count' {
        $Response = Invoke-ExecBECEvidenceExport -Request (New-Request @{ tenantFilter = 'contoso.com'; caseId = 'BEC-1' }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        $Response.Body.Results | Should -Be 'Evidence package for case BEC-1 created: 5 files, 3 KB'
        $Response.Body.Evidence.CaseId | Should -Be 'BEC-1'
        $Response.Body.Evidence.FileCount | Should -Be 5
        $Response.Body.Evidence.Bytes | Should -Be 3072
        [System.Convert]::FromBase64String($Response.Body.Evidence.ZipBase64) | Should -Be $script:ZipBytes
        Should -Invoke New-CIPPBecEvidencePackage -Times 1 -ParameterFilter { $TenantFilter -eq 'contoso.com' -and $CaseId -eq 'BEC-1' -and $APIName -eq 'ExecBECEvidenceExport' -and $Headers.'x-ms-client-principal' -eq 'x' }
        Should -Invoke Write-LogMessage -Times 0 -ParameterFilter { $sev -eq 'Error' }
    }

    It 'forwards the browser-rendered PDFs to the package builder, and passes them empty when the browser sent none' {
        $null = Invoke-ExecBECEvidenceExport -Request (New-Request @{ tenantFilter = 'contoso.com'; caseId = 'BEC-1'; pdfBase64 = 'JVBERi0x'; pdfSummaryBase64 = 'JVBERi0y' }) -TriggerMetadata $null
        Should -Invoke New-CIPPBecEvidencePackage -Times 1 -ParameterFilter { $PdfBase64 -eq 'JVBERi0x' -and $PdfSummaryBase64 -eq 'JVBERi0y' }
        $null = Invoke-ExecBECEvidenceExport -Request (New-Request @{ tenantFilter = 'contoso.com'; caseId = 'BEC-1' }) -TriggerMetadata $null
        Should -Invoke New-CIPPBecEvidencePackage -Times 1 -ParameterFilter { $CaseId -eq 'BEC-1' -and $PdfBase64 -eq '' -and $PdfSummaryBase64 -eq '' }
    }

    It 'stamps the case id on the log context while it runs and clears it afterwards' {
        $null = Invoke-ExecBECEvidenceExport -Request (New-Request @{ tenantFilter = 'contoso.com'; caseId = 'BEC-1' }) -TriggerMetadata $null
        Should -Invoke Set-CippBecCaseContext -Times 2 -Exactly
        Should -Invoke Set-CippBecCaseContext -Times 1 -ParameterFilter { $CaseId -eq 'BEC-1' }
        Should -Invoke Set-CippBecCaseContext -Times 1 -ParameterFilter { [string]::IsNullOrEmpty($CaseId) }
    }

    It 'fails cleanly without a caseId: builds nothing, logs the error and never stamps a case id it does not have' {
        $Response = Invoke-ExecBECEvidenceExport -Request (New-Request @{ tenantFilter = 'contoso.com' }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -Be 'Evidence export failed: caseId is required'
        $Response.Body.ContainsKey('Evidence') | Should -BeFalse
        Should -Invoke New-CIPPBecEvidencePackage -Times 0
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $sev -eq 'Error' -and $message -match 'caseId is required' -and $API -eq 'ExecBECEvidenceExport' -and $tenant -eq 'contoso.com' }
        Should -Invoke Set-CippBecCaseContext -Times 0 -ParameterFilter { -not [string]::IsNullOrEmpty($CaseId) }
        Should -Invoke Set-CippBecCaseContext -Times 2 -Exactly -Because 'the finally block still clears the context'
    }

    It 'fails cleanly without a tenantFilter' {
        $Response = Invoke-ExecBECEvidenceExport -Request (New-Request @{ caseId = 'BEC-1' }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -Be 'Evidence export failed: tenantFilter is required'
        Should -Invoke New-CIPPBecEvidencePackage -Times 0
        Should -Invoke Set-CippBecCaseContext -Times 1 -ParameterFilter { [string]::IsNullOrEmpty($CaseId) }
    }

    It 'reports a package build failure as a formatted error, logs it with the exception and clears the context' {
        Mock New-CIPPBecEvidencePackage { throw 'BEC run BEC-1 is Running; only completed runs can be exported' }
        $Response = Invoke-ExecBECEvidenceExport -Request (New-Request @{ tenantFilter = 'contoso.com'; caseId = 'BEC-1' }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -Be 'Evidence export failed: BEC run BEC-1 is Running; only completed runs can be exported'
        $Response.Body.ContainsKey('Evidence') | Should -BeFalse
        Should -Invoke Write-LogMessage -Times 1 -ParameterFilter { $sev -eq 'Error' -and $message -eq 'Evidence export for BEC case BEC-1 failed: BEC run BEC-1 is Running; only completed runs can be exported' -and $LogData.NormalizedError -match 'only completed runs' }
        Should -Invoke Set-CippBecCaseContext -Times 1 -ParameterFilter { $CaseId -eq 'BEC-1' }
        Should -Invoke Set-CippBecCaseContext -Times 1 -ParameterFilter { [string]::IsNullOrEmpty($CaseId) }
    }
}

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-EditIntuneScript.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-EditIntuneScript.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-GraphPOSTRequest { param($uri, $tenantid, $body, $type) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text) }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) }

    . $FunctionPath

    function ConvertTo-B64 { param($Text) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text)) }
    function ConvertFrom-B64 { param($Value) [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value)) }

    function New-ScriptRequest {
        param($Script, [string]$ScriptType = 'Windows', $ReplaceVariables)
        $Body = @{
            tenantFilter = 'contoso.com'
            ScriptId     = 'script-1'
            ScriptType   = $ScriptType
            IntuneScript = ($Script | ConvertTo-Json -Compress)
        }
        if ($null -ne $ReplaceVariables) { $Body.ReplaceVariables = $ReplaceVariables }
        [pscustomobject]@{
            Method  = 'POST'
            Params  = @{ CIPPEndpoint = 'EditIntuneScript' }
            Headers = @{}
            Body    = [pscustomobject]$Body
        }
    }
}

Describe 'Invoke-EditIntuneScript POST' {
    BeforeEach {
        $script:SentBody = $null
        Mock New-GraphPOSTRequest { $script:SentBody = $body }
        Mock Get-CIPPTextReplacement { $Text -replace '%tenantid%', 'g1' }
        Mock Write-LogMessage { }
    }

    It 'sends the script unchanged when replacement is not requested' {
        $Script = @{ id = 'script-1'; scriptContent = (ConvertTo-B64 'Write-Host %tenantid%') }
        $Request = New-ScriptRequest -Script $Script

        $Response = Invoke-EditIntuneScript -Request $Request

        $Response.StatusCode | Should -Be 200
        $script:SentBody | Should -Be $Request.Body.IntuneScript
        Should -Invoke Get-CIPPTextReplacement -Times 0 -Exactly
    }

    It 'replaces variables inside the decoded script content' {
        $Script = @{ id = 'script-1'; scriptContent = (ConvertTo-B64 'Write-Host %tenantid%') }

        $Response = Invoke-EditIntuneScript -Request (New-ScriptRequest -Script $Script -ReplaceVariables $true)

        $Response.StatusCode | Should -Be 200
        ConvertFrom-B64 ($script:SentBody | ConvertFrom-Json).scriptContent | Should -Be 'Write-Host g1'
        Should -Invoke Get-CIPPTextReplacement -ParameterFilter { $TenantFilter -eq 'contoso.com' }
    }

    It 'replaces variables in both remediation payloads' {
        $Script = @{
            id                       = 'script-1'
            detectionScriptContent   = (ConvertTo-B64 'detect %tenantid%')
            remediationScriptContent = (ConvertTo-B64 'remediate %tenantid%')
        }

        $null = Invoke-EditIntuneScript -Request (New-ScriptRequest -Script $Script -ScriptType 'Remediation' -ReplaceVariables $true)

        $Sent = $script:SentBody | ConvertFrom-Json
        ConvertFrom-B64 $Sent.detectionScriptContent | Should -Be 'detect g1'
        ConvertFrom-B64 $Sent.remediationScriptContent | Should -Be 'remediate g1'
    }

    It 'returns 400 when the script content is not base64' {
        $Script = @{ id = 'script-1'; scriptContent = 'not base64!' }

        $Response = Invoke-EditIntuneScript -Request (New-ScriptRequest -Script $Script -ReplaceVariables $true)

        $Response.StatusCode | Should -Be 400
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }
}

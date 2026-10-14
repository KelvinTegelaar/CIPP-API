# Pester tests for Push-ExecTestMessageTrace.
#
# Pins the verdict the worker records: rules named by GUID in the trace detail are Applied with
# their actions, disabled rules are Disabled, rules below an applied stop-processing rule are
# Not reached, and everything else is Not applied. A trace that never appears fails the job.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-ExecTestMessageTrace.ps1' -File | Select-Object -First 1 -ExpandProperty FullName

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-ExoRequest { param($tenantid, $cmdlet, $cmdParams) }
    function Set-CIPPAsyncDeploymentStep { param($JobId, $Name, $StepIndex, $StepStatus, $Message) }
    function Set-CIPPAsyncDeploymentStatus { param($JobId, $Name, $Status, $Logs) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Start-Sleep { param($Seconds) }

    . $FunctionPath

    $script:Item = @{ DeploymentId = 'job-1'; Name = 'b@contoso.example'; TenantFilter = 'contoso.example'; Sender = 'a@x.example'; Recipient = 'b@contoso.example'; Subject = 'Invoice 42'; SubmittedUtc = (Get-Date).ToUniversalTime().AddMinutes(-1).ToString('o') }
}

Describe 'Push-ExecTestMessageTrace' {
    BeforeEach {
        $script:Logs = $null
        Mock Set-CIPPAsyncDeploymentStep { }
        Mock Set-CIPPAsyncDeploymentStatus { if ($Logs) { $script:Logs = $Logs | ConvertFrom-Json } }
        Mock Write-LogMessage { }
        Mock Start-Sleep { }
    }

    It 'keeps reading the trace detail until it is complete, not just the first Receive event' {
        $script:DetailReads = 0
        Mock New-GraphGetRequest {
            if ($uri -like '*getDetailsByRecipient*') {
                $script:DetailReads++
                if ($script:DetailReads -eq 1) { return @([pscustomobject]@{ dateTime = 'd'; event = 'Receive'; description = 'Message received'; action = '' }) }
                @(
                    [pscustomobject]@{ dateTime = 'd'; event = 'Receive'; description = 'Message received'; action = '' }
                    [pscustomobject]@{ dateTime = 'd'; event = 'Transport rule'; description = "Transport rule: 'Stop here', ID: ('AAAAAAAA-0000-0000-0000-000000000001'), DLP policy: ''"; action = 'Remove message header' }
                    [pscustomobject]@{ dateTime = 'd'; event = 'Drop'; description = 'intentionally dropped'; action = '' }
                )
            } else {
                @([pscustomobject]@{ id = 'trace-1'; status = 'failed'; receivedDateTime = (Get-Date).ToUniversalTime().ToString('o') })
            }
        }
        Mock New-ExoRequest { @([pscustomobject]@{ Name = 'Stop here'; Guid = 'aaaaaaaa-0000-0000-0000-000000000001'; Priority = 0; State = 'Enabled'; Mode = 'Enforce'; StopRuleProcessing = $false }) }
        Push-ExecTestMessageTrace -Item $script:Item
        (@($script:Logs.Rules) | Where-Object Name -EQ 'Stop here').Result | Should -Be 'Applied'
        $script:DetailReads | Should -BeGreaterThan 2 -Because 'the detail is read until it stops growing'
    }

    It 'marks rules applied, not applied, disabled and not reached from the trace detail' {
        Mock New-GraphGetRequest {
            if ($uri -like '*getDetailsByRecipient*') {
                @(
                    [pscustomobject]@{ dateTime = 'd'; event = 'Transport rule'; description = "Transport rule: 'Stop here', ID: ('AAAAAAAA-0000-0000-0000-000000000001'), DLP policy: ''"; action = 'Redirect message' }
                    [pscustomobject]@{ dateTime = 'd2'; event = 'Transport rule'; description = "Transport rule: 'Stop here', ID: ('AAAAAAAA-0000-0000-0000-000000000001'), DLP policy: ''"; action = 'Redirect message' }
                    [pscustomobject]@{ dateTime = 'd'; event = 'Drop'; description = 'intentionally dropped'; action = '' }
                )
            } else {
                @([pscustomobject]@{ id = 'trace-1'; status = 'failed'; receivedDateTime = (Get-Date).ToUniversalTime().ToString('o') })
            }
        }
        Mock New-ExoRequest {
            @(
                [pscustomobject]@{ Name = 'Stop here'; Guid = 'aaaaaaaa-0000-0000-0000-000000000001'; Priority = 0; State = 'Enabled'; Mode = 'Enforce'; StopRuleProcessing = $true }
                [pscustomobject]@{ Name = 'Never reached'; Guid = 'aaaaaaaa-0000-0000-0000-000000000002'; Priority = 1; State = 'Enabled'; Mode = 'Enforce'; StopRuleProcessing = $false }
                [pscustomobject]@{ Name = 'Disabled one'; Guid = 'aaaaaaaa-0000-0000-0000-000000000003'; Priority = 2; State = 'Disabled'; Mode = 'Enforce'; StopRuleProcessing = $false }
            )
        }
        Push-ExecTestMessageTrace -Item $script:Item
        Should -Invoke Set-CIPPAsyncDeploymentStatus -ParameterFilter { $Status -eq 'succeeded' } -Times 1
        $Rules = @($script:Logs.Rules)
        ($Rules | Where-Object Name -EQ 'Stop here').Result | Should -Be 'Applied'
        ($Rules | Where-Object Name -EQ 'Stop here').Actions | Should -Be 'Redirect message'
        ($Rules | Where-Object Name -EQ 'Never reached').Result | Should -Be 'Not reached'
        ($Rules | Where-Object Name -EQ 'Disabled one').Result | Should -Be 'Disabled'
        @($script:Logs.Events).Count | Should -Be 3
        Should -Invoke Set-CIPPAsyncDeploymentStep -ParameterFilter { $StepIndex -eq 2 -and $StepStatus -eq 'succeeded' -and $Message -like '1 of 2 enabled rules applied' }
    }

    It 'searches the trace by recipient, sender, subject and the submission window' {
        Mock New-GraphGetRequest { @() }
        Mock New-ExoRequest { @() }
        # Each Get-Date call moves time forward so the five-minute polling deadline passes.
        $script:Clock = [datetime]::UtcNow
        Mock Get-Date { $script:Clock = $script:Clock.AddMinutes(2); $script:Clock } -ParameterFilter { -not $Format }
        Push-ExecTestMessageTrace -Item $script:Item
        Should -Invoke New-GraphGetRequest -ParameterFilter { $uri -like '*recipientAddress%20eq%20%27b%40contoso.example%27*' -and $uri -like '*senderAddress%20eq%20%27a%40x.example%27*' -and $uri -like '*contains%28subject%2C%20%27Invoice%2042%27%29*' -and $uri -like '*receivedDateTime%20ge%20*' }
    }

    It 'fails the job when the trace never shows the message' {
        Mock New-GraphGetRequest { @() }
        Mock New-ExoRequest { @() }
        # Each Get-Date call moves time forward so the five-minute polling deadline passes.
        $script:Clock = [datetime]::UtcNow
        Mock Get-Date { $script:Clock = $script:Clock.AddMinutes(2); $script:Clock } -ParameterFilter { -not $Format }
        Push-ExecTestMessageTrace -Item $script:Item
        Should -Invoke Set-CIPPAsyncDeploymentStatus -ParameterFilter { $Status -eq 'failed' } -Times 1
        Should -Invoke Set-CIPPAsyncDeploymentStep -ParameterFilter { $StepIndex -eq 1 -and $StepStatus -eq 'failed' }
    }
}

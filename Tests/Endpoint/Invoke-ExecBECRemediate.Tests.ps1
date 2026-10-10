BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    class HttpResponseContext { [int]$StatusCode; [object]$Body }
    $TypeAccelerators = [PowerShell].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ([System.Management.Automation.PSTypeName]'HttpStatusCode').Type) {
        $TypeAccelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }
    function Invoke-CIPPBecContainment { param($TenantFilter, $UserId, $UserPrincipalName, $Actions, $Parameters, [switch]$Confirmed, $CaseId, $RunResults, $Headers, $APIName) }
    function Start-CIPPBecContainmentJob { param($TenantFilter, $UserId, $UserPrincipalName, $Actions, $Parameters, $CaseId, $Headers, $APIName) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, $noPagination) }
    function Write-LogMessage { param($message, $tenant, $API, $tenantId, $headers, $user, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = [string]$Exception.Exception.Message } }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecContainmentActions.ps1')
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecBECRemediate.ps1' | Select-Object -First 1
    . $FunctionPath.FullName

    function New-Request {
        param([hashtable]$Body)
        [pscustomobject]@{
            Params  = [pscustomobject]@{ CIPPEndpoint = 'ExecBECRemediate' }
            Headers = [pscustomobject]@{ 'x-ms-client-principal' = 'x' }
            Query   = $null
            Body    = [pscustomobject]$Body
        }
    }
}

Describe 'Invoke-ExecBECRemediate' {
    BeforeEach {
        Mock Invoke-CIPPBecContainment { @([pscustomobject]@{ Action = 'RevokeSessions'; Target = 'victim@contoso.com'; state = 'success'; resultText = 'ok'; copyField = $null }) }
        Mock Start-CIPPBecContainmentJob { 'job-1' }
        Mock Write-LogMessage { }
    }

    It 'runs the default set when no actions are given and the UPN is typed' {
        $Response = Invoke-ExecBECRemediate -Request (New-Request @{ tenantFilter = 'contoso.com'; userid = 'u1'; username = 'victim@contoso.com'; Confirmation = 'Victim@Contoso.com' }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        $Response.Body.Results[0].state | Should -Be 'success'
        Should -Invoke Invoke-CIPPBecContainment -Times 1 -ParameterFilter { $Confirmed.IsPresent -and @($Actions).Count -eq 0 -and $UserPrincipalName -eq 'victim@contoso.com' }
    }

    It 'returns 400 and runs nothing when a Critical action is selected without the typed UPN' {
        $Response = Invoke-ExecBECRemediate -Request (New-Request @{ tenantFilter = 'contoso.com'; userid = 'u1'; username = 'victim@contoso.com'; Actions = @('ResetPassword', 'RevokeSessions'); Confirmation = 'wrong' }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 400
        $Response.Body.Results[0].state | Should -Be 'error'
        $Response.Body.Results[0].resultText | Should -Match 'Type the user''s UPN'
        Should -Invoke Invoke-CIPPBecContainment -Times 0
    }

    It 'lets non-Critical actions run without confirmation' {
        $Response = Invoke-ExecBECRemediate -Request (New-Request @{ tenantFilter = 'contoso.com'; userid = 'u1'; username = 'victim@contoso.com'; Actions = @('RevokeSessions', 'ClearForwarding') }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        Should -Invoke Invoke-CIPPBecContainment -Times 1 -ParameterFilter { -not $Confirmed.IsPresent -and $Actions -contains 'ClearForwarding' }
    }

    It 'accepts autocomplete-shaped action objects and hands the case on for target resolution' {
        $Response = Invoke-ExecBECRemediate -Request (New-Request @{ tenantFilter = 'contoso.com'; userid = 'u1'; username = 'victim@contoso.com'; Actions = @([pscustomobject]@{ value = 'RevokeSessions'; label = 'Revoke sessions' }); CaseId = 'BEC-1'; Parameters = [pscustomobject]@{ Protocols = @('IMAP') } }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        $Response.Body.DeploymentId | Should -BeNullOrEmpty -Because 'an inline run has nothing to poll'
        Should -Invoke Invoke-CIPPBecContainment -Times 1 -ParameterFilter { $Actions -contains 'RevokeSessions' -and $Parameters.Protocols -contains 'IMAP' -and $CaseId -eq 'BEC-1' }
    }

    It 'hands an Async run to the background job with the validated selection and returns its DeploymentId' {
        $Response = Invoke-ExecBECRemediate -Request (New-Request @{ tenantFilter = 'contoso.com'; userid = 'u1'; username = 'victim@contoso.com'; Confirmation = 'victim@contoso.com'; CaseId = 'BEC-1'; Async = $true; Parameters = [pscustomobject]@{ Protocols = @('IMAP') } }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 200
        $Response.Body.DeploymentId | Should -Be 'job-1'
        $Response.Body.Results[0].state | Should -Be 'info'
        Should -Invoke Invoke-CIPPBecContainment -Times 0
        Should -Invoke Start-CIPPBecContainmentJob -Times 1 -ParameterFilter {
            $TenantFilter -eq 'contoso.com' -and $UserPrincipalName -eq 'victim@contoso.com' -and $UserId -eq 'u1' -and $CaseId -eq 'BEC-1' -and
            $Parameters.Protocols -contains 'IMAP' -and (@($Actions) -join ',') -eq 'ResetPassword,DisableAccount,RevokeSessions,RemoveMFA,DisableInboxRules,BlockProtocols'
        }
    }

    It 'still refuses an unconfirmed Critical selection before queueing anything' {
        $Response = Invoke-ExecBECRemediate -Request (New-Request @{ tenantFilter = 'contoso.com'; userid = 'u1'; username = 'victim@contoso.com'; Async = $true }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 400
        Should -Invoke Start-CIPPBecContainmentJob -Times 0
    }

    It 'reports a job that could not be queued as an error, without a DeploymentId' {
        Mock Start-CIPPBecContainmentJob { throw "Error - The command 'Invoke-CIPPBecContainment' is not permitted to run as a scheduled task." }
        $Response = Invoke-ExecBECRemediate -Request (New-Request @{ tenantFilter = 'contoso.com'; userid = 'u1'; username = 'victim@contoso.com'; Actions = @('RevokeSessions'); Async = $true }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 500
        $Response.Body.Results[0].resultText | Should -Match 'not permitted'
        $Response.Body.DeploymentId | Should -BeNullOrEmpty
    }

    It 'rejects unknown actions' {
        $Response = Invoke-ExecBECRemediate -Request (New-Request @{ tenantFilter = 'contoso.com'; userid = 'u1'; username = 'victim@contoso.com'; Actions = @('Nuke') }) -TriggerMetadata $null
        $Response.StatusCode | Should -Be 500
        $Response.Body.Results[0].resultText | Should -Match 'Unknown containment action'
        Should -Invoke Invoke-CIPPBecContainment -Times 0
    }

    It 'resolves the UPN from the object id when only userid is supplied' {
        Mock New-GraphGetRequest { [pscustomobject]@{ userPrincipalName = 'victim@contoso.com' } }
        $null = Invoke-ExecBECRemediate -Request (New-Request @{ tenantFilter = 'contoso.com'; userid = 'u1'; Actions = @('RevokeSessions') }) -TriggerMetadata $null
        Should -Invoke Invoke-CIPPBecContainment -Times 1 -ParameterFilter { $UserPrincipalName -eq 'victim@contoso.com' -and $UserId -eq 'u1' }
    }

    It 'keeps copyField on the response rows so the password can be copied' {
        Mock Invoke-CIPPBecContainment { @([pscustomobject]@{ Action = 'ResetPassword'; Target = 'victim@contoso.com'; state = 'success'; resultText = 'The new password is x'; copyField = 'x' }) }
        $Response = Invoke-ExecBECRemediate -Request (New-Request @{ tenantFilter = 'contoso.com'; userid = 'u1'; username = 'victim@contoso.com'; Confirmation = 'victim@contoso.com' }) -TriggerMetadata $null
        $Response.Body.Results[0].copyField | Should -Be 'x'
        $Response.Body.Results[0].Action | Should -Be 'ResetPassword'
    }
}

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function New-CIPPAsyncDeployment { param($JobId, $Names, $StepTitles, $Source, $TaskId, $TenantFilter) }
    function Add-CIPPScheduledTask { param($Task, $Hidden, [switch]$RunNow, $Headers) }
    function Set-CIPPAsyncDeploymentStatus { param($JobId, $Name, $Status, $Logs) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Start-CIPPBecContainmentJob.ps1')
}

Describe 'Start-CIPPBecContainmentJob' {
    BeforeEach {
        Mock New-CIPPAsyncDeployment { 'job-1' }
        Mock Add-CIPPScheduledTask { 'Task BEC remediation: victim@contoso.com scheduled to run now' }
        Mock Set-CIPPAsyncDeploymentStatus { }
    }

    It 'creates the progress row, then queues a run-now containment task that reports to it' {
        $Id = Start-CIPPBecContainmentJob -TenantFilter 'contoso.com' -UserId 'u1' -UserPrincipalName 'victim@contoso.com' -Actions @('RevokeSessions', 'BlockProtocols') -Parameters ([pscustomobject]@{ Protocols = @('IMAP') }) -CaseId 'BEC-1' -Headers 'h'
        $Id | Should -Be 'job-1'
        Should -Invoke New-CIPPAsyncDeployment -Times 1 -ParameterFilter { $Names -contains 'victim@contoso.com' -and $Source -eq 'BECRemediation' -and $TenantFilter -eq 'contoso.com' }
        Should -Invoke Add-CIPPScheduledTask -Times 1 -ParameterFilter {
            $RunNow.IsPresent -and $Hidden -eq $false -and $Headers -eq 'h' -and
            $Task.Command.value -eq 'Invoke-CIPPBecContainment' -and $Task.TenantFilter -eq 'contoso.com' -and
            $Task.Parameters.DeploymentId -eq 'job-1' -and $Task.Parameters.CaseId -eq 'BEC-1' -and $Task.Parameters.UserId -eq 'u1' -and
            $Task.Parameters.Confirmed -and $Task.Parameters.Redacted -and $Task.Parameters.Parameters.Protocols -contains 'IMAP' -and
            (@($Task.Parameters.Actions) -join ',') -eq 'RevokeSessions,BlockProtocols'
        }
    }

    It 'throws the scheduler refusal and marks the progress row failed' {
        Mock Add-CIPPScheduledTask { "Error - The command 'Invoke-CIPPBecContainment' is not permitted to run as a scheduled task." }
        { Start-CIPPBecContainmentJob -TenantFilter 'contoso.com' -UserPrincipalName 'victim@contoso.com' -Actions @('RevokeSessions') } | Should -Throw '*not permitted*'
        Should -Invoke Set-CIPPAsyncDeploymentStatus -Times 1 -ParameterFilter { $JobId -eq 'job-1' -and $Status -eq 'failed' }
    }
}

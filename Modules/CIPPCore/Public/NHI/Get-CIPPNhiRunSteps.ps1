function Get-CIPPNhiRunSteps {
    <#
    .SYNOPSIS
        The ordered progress steps of a non-human identity (NHI) compromise investigation.
    .DESCRIPTION
        Each phase is its own Push-NHIRun job, queued in this order as one sequential orchestration, and
        reports to its step of the async-deployment row. This is the single definition of those phases so
        the run, the endpoint that queues it and the page that renders the steps agree on the list. The
        last step is always the address verdicts, score and report.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    @(
        [pscustomobject]@{ Key = 'Subject'; Title = 'The app: credentials, owners, access and Identity Protection'; Running = 'Reading the app, its credentials, owners, access and risk' }
        [pscustomobject]@{ Key = 'Changes'; Title = 'Changes made to the app'; Running = 'Reading the directory audit log for changes to the app' }
        [pscustomobject]@{ Key = 'SignIns'; Title = 'Sign-ins of the app in the window'; Running = 'Reading the sign-ins of the app in the window' }
        [pscustomobject]@{ Key = 'Baseline'; Title = 'Sign-in baseline before the window'; Running = 'Reading the sign-ins of the app before the window' }
        [pscustomobject]@{ Key = 'DelegatedUse'; Title = 'Users signing in to the app'; Running = 'Reading the sign-ins and consents of users to the app' }
        [pscustomobject]@{ Key = 'DirectoryActions'; Title = 'What the app changed in the directory'; Running = 'Reading the directory audit log for changes the app made' }
        [pscustomobject]@{ Key = 'WorkloadBaseline'; Title = 'Mail and files the app reached before the window'; Running = 'Searching the unified audit log for what the app reached before the window' }
        [pscustomobject]@{ Key = 'WorkloadActivity'; Title = 'Mail and files the app reached'; Running = 'Searching the unified audit log for mail and file activity of the app' }
        [pscustomobject]@{ Key = 'Score'; Title = 'Address verdicts, threat score and report'; Running = 'Judging the addresses and computing the threat score' }
    )
}

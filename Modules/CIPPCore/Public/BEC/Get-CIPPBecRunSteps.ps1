function Get-CIPPBecRunSteps {
    <#
    .SYNOPSIS
        The ordered progress steps of a BEC investigation.
    .DESCRIPTION
        Each phase is its own Push-BECRun job, queued in this order as one sequential orchestration,
        and reports to its step of the async-deployment row. This is the single definition of those
        phases so the run, the endpoint that queues it and the page that renders the steps agree on
        the list. The last step is always the location analysis, score and report.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    @(
        [pscustomobject]@{ Key = 'AuditLog'; Title = 'Unified audit log: rules, permissions, safelists and sharing'; Running = 'Searching the unified audit log' }
        [pscustomobject]@{ Key = 'SignIns'; Title = 'Sign-ins and mobile devices'; Running = 'Reading sign-ins and mobile devices' }
        [pscustomobject]@{ Key = 'MailboxRules'; Title = 'Inbox rules, safelists and sharing links'; Running = 'Reading inbox rules, safelists and sharing links' }
        [pscustomobject]@{ Key = 'SentMail'; Title = 'Sent message trace'; Running = 'Walking the sent message trace' }
        [pscustomobject]@{ Key = 'Tenant'; Title = 'Tenant users, MFA methods and applications'; Running = 'Reading tenant users, MFA methods and applications' }
        [pscustomobject]@{ Key = 'MailboxInventory'; Title = 'Mailbox state, delegations and add-ins'; Running = 'Reading mailbox state, delegations and add-ins' }
        [pscustomobject]@{ Key = 'Grants'; Title = 'Application consents'; Running = 'Reading application consents' }
        [pscustomobject]@{ Key = 'TransportRules'; Title = 'Transport rules'; Running = 'Reading transport rules and their changes' }
        [pscustomobject]@{ Key = 'ReceivedMail'; Title = 'Received mail and Defender verdicts'; Running = 'Reading the received-mail trace and Defender verdicts' }
        [pscustomobject]@{ Key = 'Directory'; Title = 'Directory audits, registered devices and non-interactive sign-ins'; Running = 'Reading directory audits, registered devices and non-interactive sign-ins' }
        [pscustomobject]@{ Key = 'Activity'; Title = 'Mailbox activity and Identity Protection'; Running = 'Reading mailbox activity counts and Identity Protection state' }
        [pscustomobject]@{ Key = 'IPAnalysis'; Title = 'Attacker IPs: sign-in baseline, IP lists and other accounts'; Running = 'Establishing attacker IPs from the sign-in baseline, IP lists and other accounts' }
        [pscustomobject]@{ Key = 'AttackerActivity'; Title = 'Attacker activity: mail, files, sharing links, Forms and delegated mailboxes'; Running = 'Reading what the attacker addresses opened, sent, downloaded and shared' }
        [pscustomobject]@{ Key = 'Score'; Title = 'Location analysis, threat score and report'; Running = 'Resolving locations and computing the threat score' }
    )
}

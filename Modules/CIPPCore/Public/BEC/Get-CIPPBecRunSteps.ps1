function Get-CIPPBecRunSteps {
    <#
    .SYNOPSIS
        The ordered progress steps of a BEC investigation.
    .DESCRIPTION
        Push-BECRun reports its progress through the async-deployment rows (the same mechanism the
        SharePoint template deployment uses), one step per phase. This is the single definition of
        those phases so the run, the endpoint that queues it and the page that renders the steps
        agree on the list. The last step is always the location analysis, score and report.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    @(
        [pscustomobject]@{ Key = 'AuditLog'; Title = 'Unified audit log: rules, permissions, safelists and sharing' }
        [pscustomobject]@{ Key = 'SignIns'; Title = 'Sign-ins and mobile devices' }
        [pscustomobject]@{ Key = 'MailboxRules'; Title = 'Inbox rules, safelists and sharing links' }
        [pscustomobject]@{ Key = 'SentMail'; Title = 'Sent message trace' }
        [pscustomobject]@{ Key = 'Tenant'; Title = 'Tenant users, MFA methods and applications' }
        [pscustomobject]@{ Key = 'MailboxInventory'; Title = 'Mailbox state, delegations and add-ins' }
        [pscustomobject]@{ Key = 'Grants'; Title = 'Application consents' }
        [pscustomobject]@{ Key = 'TransportRules'; Title = 'Transport rules' }
        [pscustomobject]@{ Key = 'ReceivedMail'; Title = 'Received mail and Defender verdicts' }
        [pscustomobject]@{ Key = 'Directory'; Title = 'Directory audits, registered devices and non-interactive sign-ins' }
        [pscustomobject]@{ Key = 'Activity'; Title = 'Mailbox activity and Identity Protection' }
        [pscustomobject]@{ Key = 'IPAnalysis'; Title = 'Attacker IPs: sign-in baseline, IP lists and other accounts' }
        [pscustomobject]@{ Key = 'AttackerActivity'; Title = 'Attacker activity: mail, files, sharing links, Forms and delegated mailboxes' }
        [pscustomobject]@{ Key = 'Score'; Title = 'Location analysis, threat score and report' }
    )
}

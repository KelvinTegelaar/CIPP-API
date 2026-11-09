function Get-SherwebMinimumQuantity {
    <#
    .SYNOPSIS
        Works out how far a Sherweb subscription's quantity may currently be decreased.

    .DESCRIPTION
        Subscriptions with a commitment term (Microsoft NCE monthly, annual and multi-year plans) can only
        be decreased during a short window after each purchase or renewal. Sherweb describes that window
        in commitmentTerm.committedMinimalQuantities: each entry is a quantity the subscription may be
        reduced to, valid until the committedUntil date. Once every entry has expired the quantity is
        locked at its current value until the next renewal, and Sherweb rejects any decrease with a 412
        commitment-term-violations error.

        Returns $null when the subscription carries no commitment term or Sherweb supplied no committed
        minimal quantities, meaning no restriction is known and the caller should let Sherweb decide.
        Otherwise returns an object with the lowest quantity currently allowed, the last day that floor
        applies (or $null when no decrease is allowed at all), and the date the term next renews.

    .PARAMETER Subscription
        A subscription item as returned by Get-SherwebCurrentSubscription.

    .PARAMETER AsOf
        The date to evaluate the commitment against. Defaults to today (UTC). Exposed for testing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Subscription,

        [datetime]$AsOf = [datetime]::UtcNow
    )

    $CommitmentTerm = $Subscription.commitmentTerm
    if (-not $CommitmentTerm) { return $null }

    $Entries = @($CommitmentTerm.committedMinimalQuantities | Where-Object { $null -ne $_ -and $null -ne $_.committedUntil })
    if ($Entries.Count -eq 0) { return $null }

    $Today = $AsOf.Date
    $RenewalDate = $CommitmentTerm.renewalConfiguration.renewalDate
    $RenewsOn = if ($RenewalDate) { ([datetime]$RenewalDate).Date } else { $null }

    $Active = [System.Collections.Generic.List[pscustomobject]]::new()
    foreach ($Entry in $Entries) {
        $Until = ([datetime]$Entry.committedUntil).Date
        if ($Until -ge $Today) {
            $Active.Add([pscustomobject]@{ Quantity = [int]$Entry.quantity; Until = $Until })
        }
    }

    if ($Active.Count -eq 0) {
        # Every decrease window has closed: the quantity is committed until the term renews.
        return [pscustomobject]@{
            MinimumQuantity = [int]$Subscription.quantity
            AllowedUntil    = $null
            RenewsOn        = $RenewsOn
            TermType        = $CommitmentTerm.type
        }
    }

    $Floor = ($Active | Measure-Object -Property Quantity -Minimum).Minimum
    $Until = ($Active | Where-Object { $_.Quantity -eq $Floor } | Measure-Object -Property Until -Maximum).Maximum

    return [pscustomobject]@{
        MinimumQuantity = [int]$Floor
        AllowedUntil    = $Until
        RenewsOn        = $RenewsOn
        TermType        = $CommitmentTerm.type
    }
}
